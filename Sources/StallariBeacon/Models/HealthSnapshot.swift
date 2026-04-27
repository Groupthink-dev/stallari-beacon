import Foundation

// MARK: - DaemonHealth

public struct DaemonHealth: Codable, Sendable, Equatable {
    public let name: String
    public let restartCount24h: Int
    public let restartCount1h: Int
    public let lastExitCode: Int32?
    public let lastExitSignal: String?
    public let recentExitCodes: [Int32]
    public let heartbeatSkipCount24h: Int
    public let heartbeatStaleSeconds: Int?
    public let circuitBreakerState: String
    public let circuitBreakerTripCount24h: Int
    public let lastTracebackSignature: String?
    public let lastTracebackExceptionClass: String?
    public let stableRunSeconds: Int?

    public init(
        name: String,
        restartCount24h: Int,
        restartCount1h: Int,
        lastExitCode: Int32? = nil,
        lastExitSignal: String? = nil,
        recentExitCodes: [Int32],
        heartbeatSkipCount24h: Int,
        heartbeatStaleSeconds: Int? = nil,
        circuitBreakerState: String,
        circuitBreakerTripCount24h: Int,
        lastTracebackSignature: String? = nil,
        lastTracebackExceptionClass: String? = nil,
        stableRunSeconds: Int? = nil
    ) {
        self.name = name
        self.restartCount24h = restartCount24h
        self.restartCount1h = restartCount1h
        self.lastExitCode = lastExitCode
        self.lastExitSignal = lastExitSignal
        self.recentExitCodes = recentExitCodes
        self.heartbeatSkipCount24h = heartbeatSkipCount24h
        self.heartbeatStaleSeconds = heartbeatStaleSeconds
        self.circuitBreakerState = circuitBreakerState
        self.circuitBreakerTripCount24h = circuitBreakerTripCount24h
        self.lastTracebackSignature = lastTracebackSignature
        self.lastTracebackExceptionClass = lastTracebackExceptionClass
        self.stableRunSeconds = stableRunSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case restartCount24h = "restart_count_24h"
        case restartCount1h = "restart_count_1h"
        case lastExitCode = "last_exit_code"
        case lastExitSignal = "last_exit_signal"
        case recentExitCodes = "recent_exit_codes"
        case heartbeatSkipCount24h = "heartbeat_skip_count_24h"
        case heartbeatStaleSeconds = "heartbeat_stale_seconds"
        case circuitBreakerState = "circuit_breaker_state"
        case circuitBreakerTripCount24h = "circuit_breaker_trip_count_24h"
        case lastTracebackSignature = "last_traceback_signature"
        case lastTracebackExceptionClass = "last_traceback_exception_class"
        case stableRunSeconds = "stable_run_seconds"
    }
}

// MARK: - HealthSnapshot

public struct HealthSnapshot: Codable, Sendable, Equatable {
    public let snapshotAt: Date
    public let daemons: [DaemonHealth]
    public let lensLockContentionRate: Double?
    public let healthLoopTickRate: Double?

    public init(
        snapshotAt: Date,
        daemons: [DaemonHealth],
        lensLockContentionRate: Double? = nil,
        healthLoopTickRate: Double? = nil
    ) {
        self.snapshotAt = snapshotAt
        self.daemons = daemons
        self.lensLockContentionRate = lensLockContentionRate
        self.healthLoopTickRate = healthLoopTickRate
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotAt = "snapshot_at"
        case daemons
        case lensLockContentionRate = "lens_lock_contention_rate"
        case healthLoopTickRate = "health_loop_tick_rate"
    }
}
