import Foundation

/// User preferences for Beacon. Persisted to `~/.config/sidereal/beacon/config.json`.
///
/// All telemetry is **opt-in** — both `crashReportsEnabled` and `diagnosticsEnabled`
/// default to `false`. The `reviewBeforeSending` flag (default `true`) ensures the user
/// can inspect every report before it leaves the machine.
public struct BeaconConfig: Codable, Sendable, Equatable {
    /// Whether crash reports are collected and queued for sending.
    public var crashReportsEnabled: Bool

    /// Whether periodic diagnostic snapshots are collected.
    public var diagnosticsEnabled: Bool

    /// Whether the user must approve each report before it is sent.
    public var reviewBeforeSending: Bool

    /// Ingest endpoint URL.
    public var ingestUrl: String

    /// Stable anonymous device identifier (generated once, persisted).
    public let deviceId: String

    public init(
        crashReportsEnabled: Bool = false,
        diagnosticsEnabled: Bool = false,
        reviewBeforeSending: Bool = true,
        ingestUrl: String = "https://beacon.sidereal.cc/api/v1/reports",
        deviceId: String = UUID().uuidString
    ) {
        self.crashReportsEnabled = crashReportsEnabled
        self.diagnosticsEnabled = diagnosticsEnabled
        self.reviewBeforeSending = reviewBeforeSending
        self.ingestUrl = ingestUrl
        self.deviceId = deviceId
    }

    private enum CodingKeys: String, CodingKey {
        case crashReportsEnabled = "crash_reports_enabled"
        case diagnosticsEnabled = "diagnostics_enabled"
        case reviewBeforeSending = "review_before_sending"
        case ingestUrl = "ingest_url"
        case deviceId = "device_id"
    }

    // MARK: - Persistence

    private static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sidereal/beacon", isDirectory: true)
    }

    private static var configFileURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    /// Load config from disk, returning defaults with a fresh `deviceId` if the
    /// file doesn't exist or can't be decoded.
    public static func load() -> BeaconConfig {
        let url = configFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BeaconConfig()
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(BeaconConfig.self, from: data)
        } catch {
            return BeaconConfig()
        }
    }

    /// Persist current config to disk. Creates intermediate directories if needed.
    public func save() throws {
        let dir = Self.configDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Self.configFileURL, options: .atomic)
    }
}
