import Foundation

// MARK: - ProcessGuardian protocol

/// Protocol for the process guardian dependency, allowing diagnostic collection
/// to read subprocess state without a hard coupling to the concrete type.
///
/// The concrete `ProcessGuardian` (in the Guardian module) conforms to this.
/// Using a protocol here avoids a circular dependency and enables testing with
/// stubs.
public protocol ProcessGuardianProvider: Sendable {
    /// Number of child processes currently managed.
    var subprocessCount: Int { get async }

    /// Total resident set size across all managed subprocesses, in megabytes.
    var totalManagedRssMb: Int { get async }

    /// Names and availability of configured MCP servers.
    var mcpStatuses: [MCPStatus] { get async }

    /// Dispatch job statistics for the current reporting window.
    var dispatchStats: DispatchStats { get async }
}

// MARK: - DiagnosticCollector

/// Periodically captures health snapshots of the running system.
///
/// Each snapshot produces a ``DiagnosticReport`` containing subprocess counts,
/// memory usage, system memory pressure, dispatch statistics, and MCP server
/// availability. Reports are surfaced to the Beacon pipeline for scrubbing,
/// storage, and optional transmission.
public actor DiagnosticCollector {

    // MARK: - Properties

    private let guardian: any ProcessGuardianProvider
    private let interval: TimeInterval
    private var timerTask: Task<Void, Never>?

    /// Callback invoked each time a periodic snapshot is captured.
    /// Set by the Beacon orchestrator to route reports into the pipeline.
    public var onCapture: ((DiagnosticReport) async -> Void)?

    // MARK: - Init

    /// Creates a diagnostic collector.
    ///
    /// - Parameters:
    ///   - guardian: The process guardian to query for subprocess and MCP state.
    ///   - interval: Seconds between periodic captures. Defaults to 3600 (1 hour).
    public init(guardian: any ProcessGuardianProvider, interval: TimeInterval = 3600) {
        self.guardian = guardian
        self.interval = interval
    }

    // MARK: - Lifecycle

    /// Starts periodic diagnostic capture.
    ///
    /// Captures an initial snapshot immediately, then repeats at the configured
    /// interval. Safe to call multiple times — subsequent calls cancel the
    /// previous timer and restart.
    public func start() {
        stop()

        timerTask = Task { [weak self, interval] in
            // Capture immediately on start.
            if let self {
                let report = await self.captureNow()
                await self.onCapture?(report)
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                guard !Task.isCancelled else { break }

                if let self {
                    let report = await self.captureNow()
                    await self.onCapture?(report)
                }
            }
        }
    }

    /// Stops periodic diagnostic capture.
    public func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - On-demand capture

    /// Captures a diagnostic snapshot right now.
    ///
    /// Queries the process guardian for subprocess state and reads system
    /// memory pressure from Mach APIs.
    ///
    /// - Returns: A fully populated ``DiagnosticReport``.
    public func captureNow() async -> DiagnosticReport {
        let subprocessCount = await guardian.subprocessCount
        let totalManagedRss = await guardian.totalManagedRssMb
        let mcpStatuses = await guardian.mcpStatuses
        let stats = await guardian.dispatchStats
        let pressure = SystemInfo.current().memoryPressure

        return DiagnosticReport(
            subprocessCount: subprocessCount,
            totalManagedRssMb: totalManagedRss,
            systemMemoryPressure: pressure,
            dispatchStats: stats,
            mcpAvailability: mcpStatuses
        )
    }
}
