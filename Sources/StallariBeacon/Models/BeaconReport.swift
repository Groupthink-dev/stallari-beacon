import Foundation

// MARK: - ReportType

/// Classification of the report.
public enum ReportType: String, Codable, Sendable {
    case crash
    case diagnostic
    case feedback
    case security
}

// MARK: - ReportPayload

/// Associated payload discriminated by report type.
public enum ReportPayload: Sendable, Equatable {
    case crash(CrashReport)
    case diagnostic(DiagnosticReport)
    case feedback(FeedbackReport)
    case security(SecurityReport)
}

// MARK: - BeaconReport

/// Top-level report envelope. All report types share this wrapper.
///
/// The JSON representation flattens `type` and `payload` — the type string appears
/// at the top level and the payload's fields are nested under a `"payload"` key,
/// rather than using a tagged union.
///
/// ```json
/// {
///   "beacon_version": "1.1.0",
///   "report_id": "brpt_a1b2c3d4",
///   "type": "crash",
///   "timestamp": "2026-04-03T10:00:00Z",
///   "app": { ... },
///   "system": { ... },
///   "payload": { ... },
///   "install_id": "ins_a1b2c3d4e5f67890",
///   "installed_packs": [{ "name": "acme", "version": "1.2.0", ... }],
///   "active_pack": { "name": "acme", "version": "1.2.0" },
///   "rollout_channel": "stable"
/// }
/// ```
public struct BeaconReport: Sendable, Equatable {
    /// SDK version that produced this report.
    public static let beaconVersion = "1.1.0"

    /// Report ID with `brpt_` prefix and 8 random hex characters.
    public let reportId: String

    /// Classification of the report.
    public let type: ReportType

    /// When the report was created.
    public let timestamp: Date

    /// App metadata.
    public let app: AppInfo

    /// System metadata.
    public let system: SystemInfo

    /// Type-specific payload.
    public let payload: ReportPayload

    // MARK: - 1.1.0 fields (all optional for backwards compatibility)

    /// Stable per-install identifier. Generated once on first run, persisted in
    /// app support, opaque to the customer. Survives harness upgrades and pack
    /// changes; reset only on full reinstall or user-initiated wipe.
    public let installId: String?

    /// Pack inventory at the time the report was emitted.
    public let installedPacks: [InstalledPack]?

    /// The pack that was active in the foreground tool chain when the report was
    /// generated, if attribution is possible. Nil for global daemon crashes that
    /// can't be tied to a single pack.
    public let activePack: PackRef?

    /// Rollout cohort set by the operator at registry time (e.g. "stable",
    /// "beta", "canary"). Defaults to "stable".
    public let rolloutChannel: String?

    public init(
        reportId: String? = nil,
        type: ReportType,
        timestamp: Date = Date(),
        app: AppInfo,
        system: SystemInfo,
        payload: ReportPayload,
        installId: String? = nil,
        installedPacks: [InstalledPack]? = nil,
        activePack: PackRef? = nil,
        rolloutChannel: String? = nil
    ) {
        self.reportId = reportId ?? Self.generateReportId()
        self.type = type
        self.timestamp = timestamp
        self.app = app
        self.system = system
        self.payload = payload
        self.installId = installId
        self.installedPacks = installedPacks
        self.activePack = activePack
        self.rolloutChannel = rolloutChannel
    }

    // MARK: - ID generation

    /// Generate a report ID: `brpt_` prefix + 8 random hex characters.
    private static func generateReportId() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "brpt_\(hex)"
    }
}

// MARK: - Codable

extension BeaconReport: Codable {
    private enum CodingKeys: String, CodingKey {
        case beaconVersion = "beacon_version"
        case reportId = "report_id"
        case type
        case timestamp
        case app
        case system
        case payload
        case installId = "install_id"
        case installedPacks = "installed_packs"
        case activePack = "active_pack"
        case rolloutChannel = "rollout_channel"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.beaconVersion, forKey: .beaconVersion)
        try container.encode(reportId, forKey: .reportId)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(app, forKey: .app)
        try container.encode(system, forKey: .system)

        switch payload {
        case .crash(let report):
            try container.encode(report, forKey: .payload)
        case .diagnostic(let report):
            try container.encode(report, forKey: .payload)
        case .feedback(let report):
            try container.encode(report, forKey: .payload)
        case .security(let report):
            try container.encode(report, forKey: .payload)
        }

        // 1.1.0 fields — only emitted when non-nil to keep 1.0.0-shaped output
        // for reports that don't have them.
        try container.encodeIfPresent(installId, forKey: .installId)
        try container.encodeIfPresent(installedPacks, forKey: .installedPacks)
        try container.encodeIfPresent(activePack, forKey: .activePack)
        try container.encodeIfPresent(rolloutChannel, forKey: .rolloutChannel)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // beacon_version is read but not stored — it's always emitted from the static constant.
        _ = try container.decode(String.self, forKey: .beaconVersion)
        reportId = try container.decode(String.self, forKey: .reportId)
        type = try container.decode(ReportType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        app = try container.decode(AppInfo.self, forKey: .app)
        system = try container.decode(SystemInfo.self, forKey: .system)

        switch type {
        case .crash:
            payload = .crash(try container.decode(CrashReport.self, forKey: .payload))
        case .diagnostic:
            payload = .diagnostic(try container.decode(DiagnosticReport.self, forKey: .payload))
        case .feedback:
            payload = .feedback(try container.decode(FeedbackReport.self, forKey: .payload))
        case .security:
            payload = .security(try container.decode(SecurityReport.self, forKey: .payload))
        }

        // 1.1.0 fields — tolerate absence for backwards compatibility with 1.0.0 reports.
        installId = try container.decodeIfPresent(String.self, forKey: .installId)
        installedPacks = try container.decodeIfPresent([InstalledPack].self, forKey: .installedPacks)
        activePack = try container.decodeIfPresent(PackRef.self, forKey: .activePack)
        rolloutChannel = try container.decodeIfPresent(String.self, forKey: .rolloutChannel)
    }
}
