import Foundation

/// App metadata included in every report.
public struct AppInfo: Codable, Sendable, Equatable {
    /// Semantic version of the reporting app (e.g. "0.44.3.3").
    public let version: String

    /// Component identifier (e.g. "daemon", "mcp.sidereal-blade", "dispatch.daily-digest").
    public let component: String

    public init(version: String, component: String) {
        self.version = version
        self.component = component
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case component
    }
}
