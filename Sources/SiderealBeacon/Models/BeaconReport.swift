import Foundation

// MARK: - ReportType

/// Classification of the report.
public enum ReportType: String, Codable, Sendable {
    case crash
    case diagnostic
    case feedback
}

// MARK: - ReportPayload

/// Associated payload discriminated by report type.
public enum ReportPayload: Sendable, Equatable {
    case crash(CrashReport)
    case diagnostic(DiagnosticReport)
    case feedback(FeedbackReport)
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
///   "beacon_version": "1.0.0",
///   "report_id": "brpt_a1b2c3d4",
///   "type": "crash",
///   "timestamp": "2026-04-03T10:00:00Z",
///   "app": { ... },
///   "system": { ... },
///   "payload": { ... }
/// }
/// ```
public struct BeaconReport: Sendable, Equatable {
    /// SDK version that produced this report.
    public static let beaconVersion = "1.0.0"

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

    public init(
        reportId: String? = nil,
        type: ReportType,
        timestamp: Date = Date(),
        app: AppInfo,
        system: SystemInfo,
        payload: ReportPayload
    ) {
        self.reportId = reportId ?? Self.generateReportId()
        self.type = type
        self.timestamp = timestamp
        self.app = app
        self.system = system
        self.payload = payload
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
        }
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
        }
    }
}
