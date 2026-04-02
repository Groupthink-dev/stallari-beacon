import Darwin
import Foundation

// MARK: - ManagedProcess

/// A subprocess registered for resource monitoring by the Guardian.
public struct ManagedProcess: Sendable {
    /// POSIX process identifier.
    public let pid: pid_t

    /// Human-readable name (e.g. "sidereal-blade", "obsidian-lens").
    public let name: String

    /// Per-process RSS ceiling in megabytes. 0 = no limit.
    public let rssCeilingMB: Int

    /// Per-process CPU ceiling as a percentage (0–100+). 0 = no limit.
    public let cpuCeilingPercent: Double

    /// Timestamp when the process was launched.
    public let startedAt: Date

    public init(
        pid: pid_t,
        name: String,
        rssCeilingMB: Int = 0,
        cpuCeilingPercent: Double = 0,
        startedAt: Date = Date()
    ) {
        self.pid = pid
        self.name = name
        self.rssCeilingMB = rssCeilingMB
        self.cpuCeilingPercent = cpuCeilingPercent
        self.startedAt = startedAt
    }
}

// MARK: - ProcessHealth

/// Point-in-time health snapshot for a managed subprocess.
public struct ProcessHealth: Sendable {
    /// POSIX process identifier.
    public let pid: pid_t

    /// Human-readable name matching the registered `ManagedProcess`.
    public let name: String

    /// Current resident set size in megabytes.
    public let rssMB: Int

    /// Current CPU utilisation as a percentage.
    public let cpuPercent: Double

    /// Whether the process has exceeded its RSS budget.
    public let isOverRSSBudget: Bool

    /// Whether the process has exceeded its CPU budget.
    public let isOverCPUBudget: Bool

    public init(
        pid: pid_t,
        name: String,
        rssMB: Int,
        cpuPercent: Double,
        isOverRSSBudget: Bool,
        isOverCPUBudget: Bool
    ) {
        self.pid = pid
        self.name = name
        self.rssMB = rssMB
        self.cpuPercent = cpuPercent
        self.isOverRSSBudget = isOverRSSBudget
        self.isOverCPUBudget = isOverCPUBudget
    }
}

// MARK: - GuardianAction

/// Action the Guardian recommends for a managed subprocess.
public enum GuardianAction: Sendable {
    /// Process is within budget — no action needed.
    case none

    /// Process exceeded a budget threshold — first warning before escalation.
    case warn(ProcessHealth)

    /// Process remained over budget after a warning — recommend termination.
    case kill(ProcessHealth, reason: String)
}

// MARK: - GuardianDelegate

/// Delegate protocol for receiving Guardian lifecycle and enforcement events.
public protocol GuardianDelegate: AnyObject, Sendable {
    /// Called when the Guardian detects a budget violation or recommends an action.
    func guardian(_ guardian: ProcessGuardian, didDetect action: GuardianAction) async

    /// Called when a managed process is no longer alive (auto-unregistered).
    func guardian(_ guardian: ProcessGuardian, processTerminated pid: pid_t, name: String) async
}

// MARK: - ProcessGuardian

/// Monitors managed subprocesses for resource budget violations.
///
/// The Guardian polls each registered process at a configurable interval, reading
/// RSS and CPU via `proc_pidinfo`. When a process exceeds its budget the Guardian
/// issues a warning on the first offending poll, then escalates to a kill
/// recommendation if the process is still over budget on the subsequent poll.
///
/// Dead processes are automatically detected and unregistered.
public actor ProcessGuardian {

    // MARK: - Configuration

    /// Interval between resource polls.
    public let pollInterval: TimeInterval

    /// Fleet-wide memory ceiling as a percentage of total system RAM.
    /// When the combined RSS of all managed processes exceeds this fraction,
    /// `isOverFleetCeiling()` returns `true`.
    public let fleetMemoryCeilingPercent: Double

    // MARK: - State

    /// Currently registered processes keyed by PID.
    private var processes: [pid_t: ManagedProcess] = [:]

    /// PIDs that were over budget on the previous poll cycle (pending kill escalation).
    private var warnedPIDs: Set<pid_t> = []

    /// Most recent health snapshot per PID, refreshed each poll cycle.
    private var healthCache: [pid_t: ProcessHealth] = [:]

    /// Handle to the running poll task, if active.
    private var pollTask: Task<Void, Never>?

    /// Weak delegate for action callbacks.
    private weak var delegate: GuardianDelegate?

    // MARK: - Init

    /// Creates a new ProcessGuardian.
    ///
    /// - Parameters:
    ///   - pollInterval: Seconds between resource checks. Default 5.
    ///   - fleetMemoryCeilingPercent: Percentage of system RAM that triggers the fleet ceiling. Default 60.
    public init(pollInterval: TimeInterval = 5.0, fleetMemoryCeilingPercent: Double = 60.0) {
        self.pollInterval = max(pollInterval, 0.5) // floor at 500ms to avoid spin
        self.fleetMemoryCeilingPercent = min(max(fleetMemoryCeilingPercent, 1.0), 100.0)
    }

    // MARK: - Registration

    /// Register a subprocess for monitoring.
    public func register(_ process: ManagedProcess) {
        processes[process.pid] = process
    }

    /// Unregister a subprocess by PID.
    public func unregister(pid: pid_t) {
        processes.removeValue(forKey: pid)
        warnedPIDs.remove(pid)
        healthCache.removeValue(forKey: pid)
    }

    /// Set or clear the delegate that receives Guardian actions.
    public func setDelegate(_ delegate: GuardianDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Lifecycle

    /// Begin the polling loop. No-op if already running.
    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop()
        }
    }

    /// Stop the polling loop.
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Queries

    /// Returns the current health snapshot for every managed process.
    ///
    /// If no poll has run yet the array may be empty or stale.
    public func snapshot() -> [ProcessHealth] {
        Array(healthCache.values)
    }

    /// Sum of RSS across all managed processes in megabytes.
    public func totalManagedRSSMB() -> Int {
        healthCache.values.reduce(0) { $0 + $1.rssMB }
    }

    /// Whether the combined managed RSS exceeds the fleet-wide ceiling.
    public func isOverFleetCeiling() -> Bool {
        let totalSystemMB = Self.totalSystemMemoryMB()
        guard totalSystemMB > 0 else { return false }
        let ceilingMB = Int(Double(totalSystemMB) * fleetMemoryCeilingPercent / 100.0)
        return totalManagedRSSMB() > ceilingMB
    }

    // MARK: - Poll Loop

    private func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            do {
                try await Task.sleep(for: .seconds(pollInterval))
            } catch {
                // Cancellation — exit cleanly.
                break
            }
        }
    }

    private func pollOnce() async {
        var deadPIDs: [(pid_t, String)] = []
        var newHealthCache: [pid_t: ProcessHealth] = [:]

        for (pid, managed) in processes {
            // Check if the process is still alive.
            guard Self.isProcessAlive(pid) else {
                deadPIDs.append((pid, managed.name))
                continue
            }

            let (rssMB, cpuPercent) = Self.readProcessResources(pid)

            let overRSS = managed.rssCeilingMB > 0 && rssMB > managed.rssCeilingMB
            let overCPU = managed.cpuCeilingPercent > 0 && cpuPercent > managed.cpuCeilingPercent

            let health = ProcessHealth(
                pid: pid,
                name: managed.name,
                rssMB: rssMB,
                cpuPercent: cpuPercent,
                isOverRSSBudget: overRSS,
                isOverCPUBudget: overCPU
            )

            newHealthCache[pid] = health

            // Enforcement: warn → kill escalation.
            if overRSS || overCPU {
                if warnedPIDs.contains(pid) {
                    // Already warned on a previous poll — escalate to kill.
                    let reason = Self.buildKillReason(health: health, managed: managed)
                    await delegate?.guardian(self, didDetect: .kill(health, reason: reason))
                } else {
                    // First offence — warn and mark.
                    warnedPIDs.insert(pid)
                    await delegate?.guardian(self, didDetect: .warn(health))
                }
            } else {
                // Back within budget — clear the warning flag.
                warnedPIDs.remove(pid)
            }
        }

        healthCache = newHealthCache

        // Clean up dead processes.
        for (pid, name) in deadPIDs {
            unregister(pid: pid)
            await delegate?.guardian(self, processTerminated: pid, name: name)
        }
    }

    // MARK: - System Queries

    /// Total physical memory on the machine in megabytes.
    internal static func totalSystemMemoryMB() -> Int {
        var size: size_t = MemoryLayout<Int64>.size
        var memBytes: Int64 = 0
        let result = sysctlbyname("hw.memsize", &memBytes, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Int(memBytes / (1024 * 1024))
    }

    /// Check whether a PID is still alive via `kill(pid, 0)`.
    internal static func isProcessAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    /// Read RSS (MB) and CPU (%) for a process via `proc_pidinfo`.
    ///
    /// Falls back to (0, 0) if the call fails (process died, permission denied).
    internal static func readProcessResources(_ pid: pid_t) -> (rssMB: Int, cpuPercent: Double) {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)

        guard result == size else {
            return (0, 0.0)
        }

        let rssMB = Int(info.pti_resident_size / (1024 * 1024))

        // CPU: total user + system time in nanoseconds, normalised to wall-clock seconds.
        // `pti_total_user` and `pti_total_system` are in Mach absolute time units on macOS,
        // but proc_taskinfo reports them as nanoseconds. We compute a rough instantaneous
        // percentage as (total_cpu_ns / uptime_ns) * 100 * threads.
        // For a polling-based guardian, an accurate instantaneous CPU metric would require
        // delta tracking between polls. We provide a lifetime average here which is still
        // useful for detecting runaway processes (their average climbs toward 100%).
        let totalCPUNs = Double(info.pti_total_user + info.pti_total_system)
        let threads = max(Double(info.pti_threadnum), 1.0)
        let uptimeNs = ProcessInfo.processInfo.systemUptime * 1_000_000_000
        let cpuPercent: Double
        if uptimeNs > 0 {
            cpuPercent = (totalCPUNs / uptimeNs) * 100.0 / threads
        } else {
            cpuPercent = 0.0
        }

        return (rssMB, cpuPercent)
    }

    // MARK: - Helpers

    private static func buildKillReason(health: ProcessHealth, managed: ManagedProcess) -> String {
        var parts: [String] = []
        if managed.rssCeilingMB > 0 && health.rssMB > managed.rssCeilingMB {
            parts.append("RSS \(health.rssMB)MB exceeds ceiling \(managed.rssCeilingMB)MB")
        }
        if managed.cpuCeilingPercent > 0 && health.cpuPercent > managed.cpuCeilingPercent {
            parts.append(
                String(format: "CPU %.1f%% exceeds ceiling %.1f%%",
                       health.cpuPercent, managed.cpuCeilingPercent)
            )
        }
        return parts.isEmpty ? "over budget" : parts.joined(separator: "; ")
    }
}
