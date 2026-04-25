import Foundation

// MARK: - InstallState

/// How the pack was installed or last updated on this machine.
public enum InstallState: Sendable, Equatable, Hashable {
    /// Fresh install — no prior version existed.
    case fresh
    /// Upgraded from a previous version.
    case upgraded(from: String)
    /// Reinstalled over an identical version.
    case reinstalled
}

// MARK: - InstallState + Codable

extension InstallState: Codable {
    private enum CodingKeys: String, CodingKey {
        case state
        case from
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fresh:
            try container.encode("fresh", forKey: .state)
        case .upgraded(let from):
            try container.encode("upgraded", forKey: .state)
            try container.encode(from, forKey: .from)
        case .reinstalled:
            try container.encode("reinstalled", forKey: .state)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(String.self, forKey: .state)
        switch state {
        case "fresh":
            self = .fresh
        case "upgraded":
            let from = try container.decode(String.self, forKey: .from)
            self = .upgraded(from: from)
        case "reinstalled":
            self = .reinstalled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .state,
                in: container,
                debugDescription: "Unknown install state: \(state)"
            )
        }
    }
}

// MARK: - PackSource

/// Where the pack was installed from.
public enum PackSource: String, Codable, Sendable {
    case marketplace
    case sideload
    case dev
}

// MARK: - InstalledPack

/// A pack present on the machine at the time the report was emitted.
public struct InstalledPack: Codable, Sendable, Equatable, Hashable {
    /// Pack identifier (e.g. "acme-analytics").
    public let name: String

    /// Semantic version string.
    public let version: String

    /// When the pack was installed or last updated.
    public let installedAt: Date

    /// How the pack was installed.
    public let installState: InstallState

    /// Where the pack came from.
    public let source: PackSource

    public init(
        name: String,
        version: String,
        installedAt: Date,
        installState: InstallState,
        source: PackSource
    ) {
        self.name = name
        self.version = version
        self.installedAt = installedAt
        self.installState = installState
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case version
        case installedAt = "installed_at"
        case installState = "install_state"
        case source
    }
}
