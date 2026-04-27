import Foundation
import os

// MARK: - BeaconGuardianBridge

/// Bridges ``ProcessGuardian`` to the ``ProcessGuardianProvider`` protocol
/// expected by ``DiagnosticCollector``.
///
/// `ProcessGuardian` doesn't natively expose MCP statuses or dispatch stats
/// because those are domain-specific concerns that live outside the guardian.
/// This bridge provides static placeholder values for those fields, keeping
/// the diagnostic pipeline functional. The host app can supply a richer
/// provider via ``Beacon/setGuardianProvider(_:)`` if needed.
private actor BeaconGuardianBridge: ProcessGuardianProvider {
    private let guardian: ProcessGuardian

    init(guardian: ProcessGuardian) {
        self.guardian = guardian
    }

    var subprocessCount: Int {
        get async {
            await guardian.snapshot().count
        }
    }

    var totalManagedRssMb: Int {
        get async {
            await guardian.totalManagedRSSMB()
        }
    }

    var mcpStatuses: [MCPStatus] {
        get async { [] }
    }

    var dispatchStats: DispatchStats {
        get async {
            DispatchStats(jobsStarted: 0, jobsSucceeded: 0, jobsFailed: 0, since: Date())
        }
    }
}

// MARK: - Beacon

/// Top-level orchestrator for the Stallari Beacon crash reporting SDK.
///
/// `Beacon` owns every subsystem (config, scrubber, store, sender, crash
/// collector, process guardian, circuit breaker, diagnostic collector, feedback
/// collector, breadcrumb trail) and exposes a clean, high-level API that host
/// apps consume directly.
///
/// ## Lifecycle
///
/// ```swift
/// let beacon = await Beacon.configure(appVersion: "0.44.3.3", component: "daemon")
/// await beacon.start()
/// // ... app runs ...
/// await beacon.stop()
/// ```
///
/// ## Privacy guarantees
///
/// - All reports are scrubbed of PII before touching disk.
/// - Consent is checked before any network transmission.
/// - All telemetry is opt-in; `reviewBeforeSending` defaults to `true`.
public actor Beacon {

    // MARK: - Subsystems

    private var _config: BeaconConfig
    private let appInfo: AppInfo
    private let scrubber: PIIScrubber
    private let store: ReportStore
    private let breadcrumbs: BreadcrumbTrail
    private let crashCollector: CrashCollector
    private let guardian: ProcessGuardian
    private let circuitBreaker: CircuitBreaker
    private let feedbackCollector: FeedbackCollector
    private let diagnosticCollector: DiagnosticCollector

    private let logger = Logger(subsystem: "ai.stallari.beacon", category: "Beacon")

    /// Whether `start()` has been called (and `stop()` has not).
    private var isRunning = false

    /// Reusable sender for report transmission.
    private let sender: ReportSender

    /// Background task for periodic report flushing.
    private var flushTask: Task<Void, Never>?

    // MARK: - Factory

    /// Creates and configures a Beacon instance.
    ///
    /// Loads persisted config from disk (or creates defaults), wires all
    /// subsystems together, and returns a ready-to-start instance.
    ///
    /// - Parameters:
    ///   - appVersion: Semantic version of the host app (e.g. "0.44.3.3").
    ///   - component: Component identifier (e.g. "daemon", "mcp.stallari-blade").
    ///   - customScrubPatterns: Optional additional PII patterns for the scrubber.
    /// - Returns: A configured ``Beacon`` instance. Call ``start()`` to activate.
    public static func configure(
        appVersion: String,
        component: String,
        customScrubPatterns: [(pattern: String, replacement: String)] = []
    ) async -> Beacon {
        let config = BeaconConfig.load()
        let app = AppInfo(version: appVersion, component: component)

        return Beacon(config: config, appInfo: app, customScrubPatterns: customScrubPatterns)
    }

    // MARK: - Init

    /// Internal initialiser wiring all subsystems.
    ///
    /// Prefer the ``configure(appVersion:component:customScrubPatterns:)``
    /// factory method for normal usage. This initialiser is exposed for
    /// testing with injected dependencies.
    public init(
        config: BeaconConfig,
        appInfo: AppInfo,
        customScrubPatterns: [(pattern: String, replacement: String)] = [],
        store: ReportStore? = nil,
        guardian: ProcessGuardian? = nil,
        circuitBreaker: CircuitBreaker? = nil
    ) {
        self._config = config
        self.appInfo = appInfo
        self.scrubber = PIIScrubber(customPatterns: customScrubPatterns)
        let storeInstance = store ?? ReportStore()
        self.store = storeInstance
        self.sender = ReportSender(config: config, store: storeInstance)
        self.breadcrumbs = BreadcrumbTrail()
        self.crashCollector = CrashCollector(breadcrumbs: breadcrumbs)

        let guardianInstance = guardian ?? ProcessGuardian()
        self.guardian = guardianInstance
        self.circuitBreaker = circuitBreaker ?? CircuitBreaker()
        self.feedbackCollector = FeedbackCollector()

        let bridge = BeaconGuardianBridge(guardian: guardianInstance)
        self.diagnosticCollector = DiagnosticCollector(guardian: bridge)
    }

    // MARK: - Lifecycle

    /// Installs crash signal handlers, starts the process guardian, wires
    /// the diagnostic capture callback, and loads pending crashes from
    /// previous sessions.
    ///
    /// Pending crashes from prior sessions are automatically scrubbed, wrapped
    /// in report envelopes, and saved to the store.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true

        // Install crash signal handlers.
        await crashCollector.install()

        // Start process guardian polling.
        await guardian.start()

        // Wire diagnostic collector callback and start periodic capture.
        await diagnosticCollector.setOnCapture { [weak self] report in
            guard let self else { return }
            await self.handleDiagnosticCapture(report)
        }
        if _config.diagnosticsEnabled {
            await diagnosticCollector.start()
        }

        // Collect crashes from previous sessions.
        let pendingCrashes = await crashCollector.collectPendingCrashes()
        for crash in pendingCrashes {
            await saveCrashReport(crash)
        }

        // Flush any pending reports (including just-recovered crashes).
        await flushPending()

        // Start periodic flush — retries unsent reports every 5 minutes.
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.flushPending()
            }
        }

        logger.info("Beacon started — \(pendingCrashes.count) pending crash(es) recovered")
    }

    /// Stops all background activity: uninstalls crash handlers, stops the
    /// guardian polling loop, and stops diagnostic collection.
    public func stop() async {
        guard isRunning else { return }

        flushTask?.cancel()
        flushTask = nil

        // Final flush before shutdown.
        await flushPending()

        await crashCollector.uninstall()
        await guardian.stop()
        await diagnosticCollector.stop()

        isRunning = false
        logger.info("Beacon stopped")
    }

    // MARK: - Breadcrumbs

    /// Records a breadcrumb event for crash context.
    ///
    /// Breadcrumbs form a ring buffer of recent events included in crash
    /// reports. They are never sent on their own — only as part of a crash
    /// report envelope.
    ///
    /// - Parameters:
    ///   - event: Short event identifier (e.g. "mcp.start", "dispatch.begin").
    ///   - detail: Optional human-readable detail.
    public func recordBreadcrumb(event: String, detail: String? = nil) {
        breadcrumbs.record(event: event, detail: detail)
    }

    // MARK: - Manual Report Submission

    /// Scrubs, wraps, and stores a crash report.
    ///
    /// The report is scrubbed of PII, wrapped in a ``BeaconReport`` envelope
    /// with current system info, and persisted to the pending queue.
    ///
    /// - Parameters:
    ///   - crash: The crash payload.
    ///   - app: App metadata override. If `nil`, uses the app info from configure().
    public func reportCrash(_ crash: CrashReport, app: AppInfo? = nil) async throws {
        let report = BeaconReport(
            type: .crash,
            app: app ?? appInfo,
            system: SystemInfo.current(),
            payload: .crash(crash)
        )
        let scrubbed = scrubber.scrub(report)
        try await store.save(scrubbed)
        logger.info("Crash report saved: \(scrubbed.reportId)")
        await flushPending()
    }

    /// Scrubs, wraps, and stores a diagnostic report.
    ///
    /// - Parameters:
    ///   - diagnostic: The diagnostic payload.
    ///   - app: App metadata override. If `nil`, uses the app info from configure().
    public func reportDiagnostic(_ diagnostic: DiagnosticReport, app: AppInfo? = nil) async throws {
        let report = BeaconReport(
            type: .diagnostic,
            app: app ?? appInfo,
            system: SystemInfo.current(),
            payload: .diagnostic(diagnostic)
        )
        let scrubbed = scrubber.scrub(report)
        try await store.save(scrubbed)
        logger.info("Diagnostic report saved: \(scrubbed.reportId)")
        await flushPending()
    }

    /// Collects, scrubs, wraps, and stores a feedback report.
    ///
    /// Feedback is always consented (user-initiated), but still scrubbed for
    /// PII before storage.
    ///
    /// - Parameters:
    ///   - message: Free-text feedback message from the user.
    ///   - reaction: Optional quick-reaction sentiment.
    ///   - screen: The screen or view the user was on when submitting.
    public func reportFeedback(
        message: String,
        reaction: ReactionType? = nil,
        screen: String? = nil
    ) async throws {
        let feedback = await feedbackCollector.createFeedback(
            message: message,
            reaction: reaction,
            contextScreen: screen
        )
        let report = BeaconReport(
            type: .feedback,
            app: appInfo,
            system: SystemInfo.current(),
            payload: .feedback(feedback)
        )
        let scrubbed = scrubber.scrub(report)
        try await store.save(scrubbed)
        logger.info("Feedback report saved: \(scrubbed.reportId)")
        await flushPending()
    }

    // MARK: - Guardian Provider

    /// Installs a richer ``ProcessGuardianProvider`` to back the diagnostic
    /// collector. Replaces the default ``BeaconGuardianBridge`` so host apps
    /// can surface MCP statuses, dispatch stats, and per-daemon health states.
    ///
    /// Safe to call before or after ``start()``. Takes effect on the next
    /// snapshot — the in-flight snapshot (if any) keeps the previous provider.
    public func setGuardianProvider(_ provider: any ProcessGuardianProvider) async {
        await diagnosticCollector.setGuardian(provider)
    }

    // MARK: - Process Guardian

    /// Registers a subprocess for resource monitoring.
    public func registerProcess(_ process: ManagedProcess) async {
        await guardian.register(process)
    }

    /// Unregisters a subprocess by PID.
    public func unregisterProcess(pid: pid_t) async {
        await guardian.unregister(pid: pid)
    }

    /// Returns the current health snapshot for all managed subprocesses.
    public func processSnapshot() async -> [ProcessHealth] {
        await guardian.snapshot()
    }

    /// Returns the circuit breaker status for a named subprocess.
    public func circuitBreakerStatus(for name: String) async -> CircuitStatus {
        await circuitBreaker.status(name: name)
    }

    /// Records a failure for a named subprocess in the circuit breaker.
    public func recordProcessFailure(name: String) async {
        await circuitBreaker.recordFailure(name: name)
    }

    /// Whether the circuit breaker allows restarting the named subprocess.
    public func canRestartProcess(name: String) async -> Bool {
        await circuitBreaker.canRestart(name: name)
    }

    // MARK: - Report Management

    /// Returns all pending (unsent) reports, newest first.
    public func pendingReports() async throws -> [BeaconReport] {
        try await store.listPending()
    }

    /// Attempts to send all pending reports.
    ///
    /// Checks consent for each report type before transmission. Reports that
    /// fail to send remain in the pending queue for retry.
    ///
    /// - Returns: A summary of the batch send operation.
    public func sendPendingReports() async throws -> SendResult {
        try await sender.sendAllPending()
    }

    /// Deletes a single report by ID from the store.
    public func deleteReport(_ id: String) async throws {
        try await store.delete(id)
        logger.info("Report deleted: \(id)")
    }

    /// Deletes all reports and data from the store.
    ///
    /// Intended for the "Delete all data" user action. This removes both
    /// pending and sent reports.
    public func deleteAllData() async throws {
        try await store.deleteAll()
        logger.info("All beacon data deleted")
    }

    // MARK: - Config

    /// Applies a mutation to the beacon config and persists it.
    ///
    /// The transform closure receives an `inout BeaconConfig` so callers
    /// can toggle individual fields without replacing the whole struct.
    ///
    /// If diagnostics are toggled, the diagnostic collector is started or
    /// stopped accordingly.
    ///
    /// ```swift
    /// await beacon.updateConfig { config in
    ///     config.crashReportsEnabled = true
    ///     config.diagnosticsEnabled = true
    /// }
    /// ```
    public func updateConfig(_ transform: (inout BeaconConfig) -> Void) async {
        transform(&_config)
        do {
            try _config.save()
        } catch {
            logger.error("Failed to save config: \(error.localizedDescription)")
        }

        // React to diagnostics toggle.
        if _config.diagnosticsEnabled && isRunning {
            await diagnosticCollector.start()
        } else if !_config.diagnosticsEnabled {
            await diagnosticCollector.stop()
        }
    }

    /// The current beacon configuration.
    public var config: BeaconConfig {
        _config
    }

    // MARK: - Private Helpers

    /// Wraps a crash report in an envelope, scrubs it, and saves to the store.
    /// Errors are logged but never thrown — background recovery must not crash.
    private func saveCrashReport(_ crash: CrashReport) async {
        do {
            let report = BeaconReport(
                type: .crash,
                app: appInfo,
                system: SystemInfo.current(),
                payload: .crash(crash)
            )
            let scrubbed = scrubber.scrub(report)
            try await store.save(scrubbed)
        } catch {
            logger.error("Failed to save recovered crash report: \(error.localizedDescription)")
        }
    }

    /// Callback for periodic diagnostic captures. Wraps and stores the report.
    private func handleDiagnosticCapture(_ diagnostic: DiagnosticReport) async {
        do {
            try await reportDiagnostic(diagnostic)
        } catch {
            logger.error("Failed to save diagnostic report: \(error.localizedDescription)")
        }
    }

    /// Best-effort flush of pending reports. Errors are logged, never thrown.
    private func flushPending() async {
        do {
            let result = try await sender.sendAllPending()
            if result.sent > 0 {
                logger.info("Flushed \(result.sent) report(s)")
            }
            for err in result.errors {
                logger.warning("Flush error: \(err)")
            }
        } catch {
            logger.warning("Flush failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - DiagnosticCollector callback extension

extension DiagnosticCollector {
    /// Sets the capture callback. Used by the Beacon orchestrator to wire
    /// the diagnostic pipeline.
    func setOnCapture(_ callback: @escaping @Sendable (DiagnosticReport) async -> Void) {
        self.onCapture = callback
    }
}
