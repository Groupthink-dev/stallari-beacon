import Foundation

// MARK: - CircuitStatus

/// Current state of the circuit breaker for a named subprocess.
public enum CircuitStatus: Sendable {
    /// Healthy — process can restart immediately.
    case closed

    /// Backing off — the process may restart after the indicated interval elapses.
    case halfOpen(nextAttemptIn: TimeInterval)

    /// Tripped — too many failures within the window. Manual `reset(name:)` required.
    case open(failures: Int, cooldownRemaining: TimeInterval)
}

// MARK: - CircuitBreaker

/// Prevents restart loops by tracking failure history per named subprocess
/// and applying exponential backoff with a configurable trip threshold.
///
/// Backoff sequence: 1s → 2s → 4s → 8s → 16s → 32s → 60s → 120s → 300s (cap).
///
/// When a subprocess accumulates `maxFailures` within `windowMinutes`, the
/// circuit opens and `canRestart(name:)` returns `false` until the caller
/// explicitly calls `reset(name:)`.
public actor CircuitBreaker {

    // MARK: - Configuration

    /// Number of failures within the window that trips the circuit.
    public let maxFailures: Int

    /// Sliding window in minutes. Failures older than this are pruned.
    public let windowMinutes: Int

    // MARK: - Constants

    /// Exponential backoff schedule in seconds, capped at 5 minutes.
    private static let backoffSchedule: [TimeInterval] = [
        1, 2, 4, 8, 16, 32, 60, 120, 300
    ]

    // MARK: - State

    /// Failure timestamps per subprocess name.
    private var failures: [String: [Date]] = [:]

    /// Whether the circuit has been explicitly tripped (open) for a subprocess.
    private var tripped: Set<String> = []

    // MARK: - Init

    /// Creates a new CircuitBreaker.
    ///
    /// - Parameters:
    ///   - maxFailures: Failure count that trips the circuit. Default 5.
    ///   - windowMinutes: Sliding window in minutes. Default 10.
    public init(maxFailures: Int = 5, windowMinutes: Int = 10) {
        self.maxFailures = max(maxFailures, 1)
        self.windowMinutes = max(windowMinutes, 1)
    }

    // MARK: - Recording

    /// Log a failure for the named subprocess.
    ///
    /// If this pushes the failure count (within the window) to `maxFailures`
    /// or above, the circuit trips to open.
    public func recordFailure(name: String) {
        let now = Date()
        var history = pruned(failures[name] ?? [], before: now)
        history.append(now)
        failures[name] = history

        if history.count >= maxFailures {
            tripped.insert(name)
        }
    }

    // MARK: - Queries

    /// Whether the named subprocess may attempt a restart.
    ///
    /// Returns `false` if the circuit is open (tripped) or the backoff period
    /// has not yet elapsed.
    public func canRestart(name: String) -> Bool {
        // If tripped, the circuit is open — no restarts until manual reset.
        if tripped.contains(name) {
            return false
        }

        let history = pruned(failures[name] ?? [], before: Date())

        // No recent failures — go ahead.
        guard !history.isEmpty else { return true }

        // Check backoff.
        let interval = backoffForCount(history.count)
        guard let lastFailure = history.last else { return true }
        return Date().timeIntervalSince(lastFailure) >= interval
    }

    /// The current backoff interval for the named subprocess in seconds.
    ///
    /// Returns 0 if there are no recent failures.
    public func backoffInterval(name: String) -> TimeInterval {
        let history = pruned(failures[name] ?? [], before: Date())
        guard !history.isEmpty else { return 0 }
        return backoffForCount(history.count)
    }

    /// Current circuit status for the named subprocess.
    public func status(name: String) -> CircuitStatus {
        let now = Date()
        let history = pruned(failures[name] ?? [], before: now)

        // Open (tripped).
        if tripped.contains(name) {
            // Cooldown is the window duration from the most recent failure.
            let cooldown: TimeInterval
            if let last = history.last {
                let windowEnd = last.addingTimeInterval(TimeInterval(windowMinutes * 60))
                cooldown = max(windowEnd.timeIntervalSince(now), 0)
            } else {
                cooldown = 0
            }
            return .open(failures: history.count, cooldownRemaining: cooldown)
        }

        // No recent failures — closed.
        guard !history.isEmpty, let lastFailure = history.last else {
            return .closed
        }

        // Check if we're still in a backoff period.
        let interval = backoffForCount(history.count)
        let elapsed = now.timeIntervalSince(lastFailure)

        if elapsed < interval {
            return .halfOpen(nextAttemptIn: interval - elapsed)
        }

        return .closed
    }

    // MARK: - Reset

    /// Clear all failure history for the named subprocess, closing the circuit.
    public func reset(name: String) {
        failures.removeValue(forKey: name)
        tripped.remove(name)
    }

    /// Clear all failure history for every subprocess.
    public func resetAll() {
        failures.removeAll()
        tripped.removeAll()
    }

    // MARK: - Internals

    /// Remove failure timestamps older than the sliding window.
    private func pruned(_ history: [Date], before now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-TimeInterval(windowMinutes * 60))
        return history.filter { $0 > cutoff }
    }

    /// Look up the backoff interval for a given failure count.
    private func backoffForCount(_ count: Int) -> TimeInterval {
        let index = min(count - 1, Self.backoffSchedule.count - 1)
        guard index >= 0 else { return 0 }
        return Self.backoffSchedule[index]
    }
}
