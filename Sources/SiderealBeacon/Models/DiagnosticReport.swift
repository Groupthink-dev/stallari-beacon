import Foundation

// MARK: - DispatchStats

/// Dispatch job statistics over a time window.
public struct DispatchStats: Codable, Sendable, Equatable {
    /// Total jobs started in the window.
    public let jobsStarted: Int

    /// Jobs that completed successfully.
    public let jobsSucceeded: Int

    /// Jobs that failed.
    public let jobsFailed: Int

    /// Start of the statistics window (ISO 8601).
    public let since: Date

    public init(jobsStarted: Int, jobsSucceeded: Int, jobsFailed: Int, since: Date) {
        self.jobsStarted = jobsStarted
        self.jobsSucceeded = jobsSucceeded
        self.jobsFailed = jobsFailed
        self.since = since
    }

    private enum CodingKeys: String, CodingKey {
        case jobsStarted = "jobs_started"
        case jobsSucceeded = "jobs_succeeded"
        case jobsFailed = "jobs_failed"
        case since
    }
}

// MARK: - MCPStatus

/// Availability status of a single MCP server.
public struct MCPStatus: Codable, Sendable, Equatable {
    /// MCP server name (e.g. "sidereal-blade", "fastmail-blade").
    public let name: String

    /// Whether the MCP server is currently reachable.
    public let isAvailable: Bool

    public init(name: String, isAvailable: Bool) {
        self.name = name
        self.isAvailable = isAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case isAvailable = "is_available"
    }
}

// MARK: - DiagnosticReport

/// Periodic health snapshot payload sent at configurable intervals.
public struct DiagnosticReport: Codable, Sendable, Equatable {
    /// Number of child processes managed by the daemon.
    public let subprocessCount: Int

    /// Total RSS across all managed subprocesses in megabytes.
    public let totalManagedRssMb: Int

    /// System memory pressure at capture time.
    public let systemMemoryPressure: MemoryPressure

    /// Dispatch job statistics for the reporting window.
    public let dispatchStats: DispatchStats

    /// Availability of configured MCP servers.
    public let mcpAvailability: [MCPStatus]

    public init(
        subprocessCount: Int,
        totalManagedRssMb: Int,
        systemMemoryPressure: MemoryPressure,
        dispatchStats: DispatchStats,
        mcpAvailability: [MCPStatus] = []
    ) {
        self.subprocessCount = subprocessCount
        self.totalManagedRssMb = totalManagedRssMb
        self.systemMemoryPressure = systemMemoryPressure
        self.dispatchStats = dispatchStats
        self.mcpAvailability = mcpAvailability
    }

    private enum CodingKeys: String, CodingKey {
        case subprocessCount = "subprocess_count"
        case totalManagedRssMb = "total_managed_rss_mb"
        case systemMemoryPressure = "system_memory_pressure"
        case dispatchStats = "dispatch_stats"
        case mcpAvailability = "mcp_availability"
    }
}
