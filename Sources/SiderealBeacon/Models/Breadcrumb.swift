import Foundation

/// An event in the timeline leading to a crash.
///
/// The `t` field is seconds relative to the crash moment — negative values
/// indicate events that occurred before the crash.
public struct Breadcrumb: Codable, Sendable, Equatable {
    /// Seconds relative to crash (negative = before crash).
    public let t: TimeInterval

    /// Short event identifier (e.g. "mcp.start", "dispatch.begin").
    public let event: String

    /// Optional human-readable detail.
    public let detail: String?

    public init(t: TimeInterval, event: String, detail: String? = nil) {
        self.t = t
        self.event = event
        self.detail = detail
    }
}
