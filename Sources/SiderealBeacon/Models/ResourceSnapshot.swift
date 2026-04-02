import Foundation

/// Point-in-time resource state captured at the moment of a crash or diagnostic event.
public struct ResourceSnapshot: Codable, Sendable, Equatable {
    /// Resident set size of the main process in megabytes.
    public let rssMb: Int

    /// CPU utilisation as a percentage (0–100+).
    public let cpuPercent: Double

    /// Number of child processes managed by the daemon.
    public let subprocessCount: Int

    /// Total RSS across all managed subprocesses in megabytes.
    public let totalManagedRssMb: Int

    public init(rssMb: Int, cpuPercent: Double, subprocessCount: Int, totalManagedRssMb: Int) {
        self.rssMb = rssMb
        self.cpuPercent = cpuPercent
        self.subprocessCount = subprocessCount
        self.totalManagedRssMb = totalManagedRssMb
    }

    private enum CodingKeys: String, CodingKey {
        case rssMb = "rss_mb"
        case cpuPercent = "cpu_percent"
        case subprocessCount = "subprocess_count"
        case totalManagedRssMb = "total_managed_rss_mb"
    }
}
