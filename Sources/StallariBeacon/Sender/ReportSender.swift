import Foundation

// MARK: - SendError

/// Errors that can occur during report transmission.
public enum SendError: Error, Sendable {
    /// The report type is not consented by the user.
    case notConsented

    /// A network-level failure (DNS, timeout, connection refused, etc.).
    case networkError(underlying: any Error)

    /// The server returned a non-success status code.
    case serverError(statusCode: Int, body: String)

    /// The report could not be JSON-encoded.
    case encodingError
}

// MARK: - SendResult

/// Summary of a batch send operation.
public struct SendResult: Sendable, Equatable {
    /// Number of reports successfully sent.
    public let sent: Int

    /// Number of reports that failed to send.
    public let failed: Int

    /// Human-readable descriptions of each failure.
    public let errors: [String]

    public init(sent: Int, failed: Int, errors: [String]) {
        self.sent = sent
        self.failed = failed
        self.errors = errors
    }
}

// MARK: - ReportSender

/// Transmits consented crash reports, diagnostics, and feedback over HTTPS.
///
/// Reports are POST-ed as JSON to the configured ingest URL. The sender
/// respects user consent — reports whose type is not consented are rejected
/// before any network call. On success the backing ``ReportStore`` is told
/// to mark the report as sent so it moves out of the pending queue.
public actor ReportSender {

    private let config: BeaconConfig
    private let store: any ReportStore
    private let session: URLSession
    private let gate: ConsentGate
    private let outboundGate: OutboundGate?
    private let encoder: JSONEncoder

    /// Create a sender wired to the given config and local report store.
    ///
    /// - Parameters:
    ///   - config: Beacon configuration (ingest URL, consent state).
    ///   - store: Local report persistence layer (protocol-typed since
    ///     DD-270 Phase A — file-backed default, harness injects
    ///     `EncryptedReportStore`).
    ///   - session: URL session to use for HTTP calls. Defaults to `.shared`.
    ///   - outboundGate: Per-flush verdict closure honouring DD-270's user
    ///     mode setting. `nil` is **fail-closed** (AUD-05-05 / CONV-19): a
    ///     sender with no gate treats every flush as `.suppressed` and never
    ///     touches the network. A consumer that wants outbound traffic MUST
    ///     wire an explicit gate that returns its consented verdict; the
    ///     harness wires a real closure at daemon boot. (Prior to DD-397
    ///     Phase C the default was `.permitted`, which let an external SDK
    ///     consumer that forgot to wire the gate phone home unconsented.)
    public init(
        config: BeaconConfig,
        store: any ReportStore,
        session: URLSession = .shared,
        outboundGate: OutboundGate? = nil
    ) {
        self.config = config
        self.store = store
        self.session = session
        self.gate = ConsentGate(config: config)
        self.outboundGate = outboundGate

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: - Single report

    /// Send a single report to the ingest endpoint.
    ///
    /// Checks consent, encodes the report, POSTs it, and marks it as sent
    /// in the store on success.
    ///
    /// - Throws: ``SendError`` on consent failure, encoding failure, network
    ///   error, or non-2xx response.
    public func send(_ report: BeaconReport) async throws {
        // Consent gate — blocks before any network I/O.
        try gate.check(report)

        let body: Data
        do {
            body = try encoder.encode(report)
        } catch {
            throw SendError.encodingError
        }

        guard let url = URL(string: config.ingestUrl) else {
            throw SendError.networkError(underlying: URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SendError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SendError.networkError(
                underlying: URLError(.badServerResponse)
            )
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
            throw SendError.serverError(statusCode: http.statusCode, body: preview)
        }

        // Success — move the report out of the pending queue.
        try await store.markSent(report.reportId)
    }

    // MARK: - Retry wrapper

    /// Send a report with exponential backoff on transient failures.
    ///
    /// Retries on 5xx server errors and network errors. 4xx responses are
    /// treated as permanent failures and are not retried.
    ///
    /// - Parameters:
    ///   - report: The report to send.
    ///   - maxAttempts: Total number of attempts (including the first). Defaults to 3.
    public func sendWithRetry(
        _ report: BeaconReport,
        maxAttempts: Int = 3
    ) async throws {
        var lastError: SendError?

        for attempt in 0 ..< maxAttempts {
            do {
                try await send(report)
                return // success
            } catch let error as SendError {
                switch error {
                case .serverError(let statusCode, _) where statusCode >= 500:
                    // Transient — retry after backoff.
                    lastError = error
                case .networkError:
                    // Transient — retry after backoff.
                    lastError = error
                default:
                    // Permanent failure (4xx, consent, encoding) — do not retry.
                    throw error
                }
            }

            // Exponential backoff: 1s, 2s, 4s, ...
            if attempt < maxAttempts - 1 {
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }

        // All attempts exhausted.
        if let lastError {
            throw lastError
        }
    }

    // MARK: - Outbound gate

    /// Consult the host-supplied ``OutboundGate`` and return the pending
    /// reports that would be flushed under the current verdict.
    ///
    /// - `.suppressed` (or no gate wired) → returns `[]` without consulting
    ///   the store. A missing gate is fail-closed (AUD-05-05 / CONV-19).
    /// - `.crashOnly` → returns only pending reports with `.crash` payload.
    /// - `.permitted` → returns the full pending list.
    ///
    /// Public so tests can verify the gate behaviour without mocking
    /// ``URLSession``. Phase 0 chokepoint per
    /// `[[DD-270-implementation-plan]]`.
    public func sendableReports() async throws -> [BeaconReport] {
        let decision = await outboundGate?() ?? .suppressed
        switch decision {
        case .suppressed:
            return []
        case .crashOnly:
            let all = try await store.listPending()
            return all.filter { $0.type == .crash }
        case .permitted:
            return try await store.listPending()
        }
    }

    // MARK: - Batch send

    /// Attempt to send all pending reports, returning a summary.
    ///
    /// Each report is sent with retry. Failures for individual reports do
    /// not abort the batch — the caller receives a ``SendResult`` describing
    /// what succeeded and what did not.
    ///
    /// The host-supplied ``OutboundGate`` is consulted *before* any network
    /// I/O — when the verdict is `.suppressed` the method returns
    /// `SendResult(sent: 0, failed: 0, errors: [])` without ever touching
    /// the store loop or the URL session. DD-270 Phase 0 / convention #19.
    public func sendAllPending() async throws -> SendResult {
        let pending = try await sendableReports()

        var sent = 0
        var failed = 0
        var errors: [String] = []

        for report in pending {
            do {
                try await sendWithRetry(report)
                sent += 1
            } catch let error as SendError {
                failed += 1
                errors.append(describeError(error, reportId: report.reportId))
            } catch {
                failed += 1
                errors.append("\(report.reportId): \(error.localizedDescription)")
            }
        }

        return SendResult(sent: sent, failed: failed, errors: errors)
    }

    // MARK: - Private helpers

    private func describeError(_ error: SendError, reportId: String) -> String {
        switch error {
        case .notConsented:
            return "\(reportId): not consented"
        case .networkError(let underlying):
            return "\(reportId): network error — \(underlying.localizedDescription)"
        case .serverError(let statusCode, let body):
            let preview = body.prefix(128)
            return "\(reportId): server error \(statusCode) — \(preview)"
        case .encodingError:
            return "\(reportId): encoding error"
        }
    }
}
