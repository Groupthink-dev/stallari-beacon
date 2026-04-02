import Foundation

// MARK: - CrashType

/// Classification of crash origin.
public enum CrashType: String, Codable, Sendable {
    case memoryPressure = "memory_pressure"
    case signalAbort = "signal_abort"
    case unhandledException = "unhandled_exception"
    case machException = "mach_exception"
    case watchdogTimeout = "watchdog_timeout"
}

// MARK: - CrashReport

/// Crash-specific payload containing the crash classification, resource state at
/// the time of the crash, breadcrumb trail, and a symbolic stack trace.
public struct CrashReport: Codable, Sendable, Equatable {
    /// Classification of the crash.
    public let type: CrashType

    /// POSIX signal name if applicable (e.g. "SIGABRT", "SIGSEGV").
    public let signal: String?

    /// Jetsam reason string from the OS, if memory-pressure related.
    public let jetsamReason: String?

    /// Resource snapshot at the moment of crash.
    public let resourceSnapshot: ResourceSnapshot

    /// Breadcrumb trail leading up to the crash (most recent last).
    public let breadcrumbs: [Breadcrumb]

    /// Symbolic stack trace frames.
    public let stackTrace: [String]

    public init(
        type: CrashType,
        signal: String? = nil,
        jetsamReason: String? = nil,
        resourceSnapshot: ResourceSnapshot,
        breadcrumbs: [Breadcrumb] = [],
        stackTrace: [String] = []
    ) {
        self.type = type
        self.signal = signal
        self.jetsamReason = jetsamReason
        self.resourceSnapshot = resourceSnapshot
        self.breadcrumbs = breadcrumbs
        self.stackTrace = stackTrace
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case signal
        case jetsamReason = "jetsam_reason"
        case resourceSnapshot = "resource_snapshot"
        case breadcrumbs
        case stackTrace = "stack_trace"
    }
}
