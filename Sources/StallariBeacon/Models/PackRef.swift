import Foundation

// MARK: - PackRef

/// Lightweight reference to a pack name and version, used to attribute a report
/// to the pack that was active when the event occurred.
public struct PackRef: Codable, Sendable, Equatable, Hashable {
    /// Pack identifier (e.g. "acme-analytics").
    public let name: String

    /// Semantic version string.
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}
