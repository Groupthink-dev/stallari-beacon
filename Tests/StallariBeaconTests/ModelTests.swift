import Foundation
import Testing

@testable import StallariBeacon

// MARK: - Model Tests

@Suite("Models")
struct ModelTests {

    // MARK: - Report ID format

    @Test("Report ID starts with brpt_ prefix and has 13 characters total")
    func reportIdFormat() {
        let report = BeaconReport(
            type: .crash,
            app: AppInfo(version: "1.0.0", component: "test"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .crash(CrashReport(
                type: .signalAbort,
                resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 30.0, subprocessCount: 2, totalManagedRssMb: 200)
            ))
        )

        #expect(report.reportId.hasPrefix("brpt_"))
        #expect(report.reportId.count == 13) // "brpt_" (5) + 8 hex chars
    }

    @Test("Generated report IDs are unique")
    func reportIdUniqueness() {
        let ids = (0 ..< 100).map { _ in
            BeaconReport(
                type: .crash,
                app: AppInfo(version: "1.0.0", component: "test"),
                system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
                payload: .crash(CrashReport(
                    type: .signalAbort,
                    resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 30.0, subprocessCount: 2, totalManagedRssMb: 200)
                ))
            ).reportId
        }

        let unique = Set(ids)
        #expect(unique.count == 100)
    }

    // MARK: - Codable round-trip: crash

    @Test("Crash report Codable round-trip")
    func crashCodableRoundTrip() throws {
        let crash = CrashReport(
            type: .machException,
            signal: "SIGSEGV",
            jetsamReason: nil,
            resourceSnapshot: ResourceSnapshot(rssMb: 512, cpuPercent: 88.5, subprocessCount: 7, totalManagedRssMb: 2048),
            breadcrumbs: [
                Breadcrumb(t: -3.0, event: "dispatch.start", detail: "daily-digest"),
                Breadcrumb(t: -0.5, event: "mcp.call", detail: nil),
            ],
            stackTrace: ["frame0", "frame1"]
        )

        let original = BeaconReport(
            reportId: "brpt_aabb1122",
            type: .crash,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "0.44.3.3", component: "daemon"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .crash(crash)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BeaconReport.self, from: data)

        #expect(decoded.reportId == original.reportId)
        #expect(decoded.type == .crash)
        #expect(decoded.app == original.app)
        #expect(decoded.system == original.system)
        #expect(decoded.payload == original.payload)
    }

    // MARK: - Codable round-trip: diagnostic

    @Test("Diagnostic report Codable round-trip")
    func diagnosticCodableRoundTrip() throws {
        let diagnostic = DiagnosticReport(
            subprocessCount: 5,
            totalManagedRssMb: 1024,
            systemMemoryPressure: .warn,
            dispatchStats: DispatchStats(
                jobsStarted: 20,
                jobsSucceeded: 18,
                jobsFailed: 2,
                since: Date(timeIntervalSinceReferenceDate: 799_000_000)
            ),
            mcpAvailability: [
                MCPStatus(name: "stallari-blade", isAvailable: true),
                MCPStatus(name: "fastmail-blade", isAvailable: false),
            ]
        )

        let original = BeaconReport(
            reportId: "brpt_diag0001",
            type: .diagnostic,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "0.44.3.3", component: "daemon"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .warn),
            payload: .diagnostic(diagnostic)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BeaconReport.self, from: data)

        #expect(decoded.type == .diagnostic)
        #expect(decoded.payload == original.payload)
    }

    // MARK: - Codable round-trip: feedback

    @Test("Feedback report Codable round-trip")
    func feedbackCodableRoundTrip() throws {
        let feedback = FeedbackReport(
            message: "The sidebar flickers on launch",
            reaction: .loveIt,
            contextScreen: "settings.general",
            includesDiagnosticBundle: true
        )

        let original = BeaconReport(
            reportId: "brpt_feed0001",
            type: .feedback,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "0.44.3.3", component: "app"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .feedback(feedback)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BeaconReport.self, from: data)

        #expect(decoded.type == .feedback)
        #expect(decoded.payload == original.payload)
    }

    // MARK: - CrashType raw values

    @Test("CrashType raw values match wire format")
    func crashTypeRawValues() {
        #expect(CrashType.memoryPressure.rawValue == "memory_pressure")
        #expect(CrashType.signalAbort.rawValue == "signal_abort")
        #expect(CrashType.unhandledException.rawValue == "unhandled_exception")
        #expect(CrashType.machException.rawValue == "mach_exception")
        #expect(CrashType.watchdogTimeout.rawValue == "watchdog_timeout")
    }

    // MARK: - MemoryPressure raw values

    @Test("MemoryPressure raw values match wire format")
    func memoryPressureRawValues() {
        #expect(MemoryPressure.nominal.rawValue == "nominal")
        #expect(MemoryPressure.warn.rawValue == "warn")
        #expect(MemoryPressure.critical.rawValue == "critical")
    }

    // MARK: - ReactionType raw values

    @Test("ReactionType raw values match wire format")
    func reactionTypeRawValues() {
        #expect(ReactionType.works.rawValue == "works")
        #expect(ReactionType.broken.rawValue == "broken")
        #expect(ReactionType.confused.rawValue == "confused")
        #expect(ReactionType.loveIt.rawValue == "love_it")
    }

    // MARK: - SystemInfo.current()

    @Test("SystemInfo.current() returns valid data")
    func systemInfoCurrent() {
        let info = SystemInfo.current()

        // OS version should be non-empty and contain dots
        #expect(!info.osVersion.isEmpty)
        #expect(info.osVersion.contains("."))

        // Arch should be a known value
        #expect(info.arch == "arm64" || info.arch == "x86_64")

        // Memory should be positive
        #expect(info.memoryGb > 0)

        // Memory pressure should be a valid case (it always is, just verify it decoded)
        let validPressures: [MemoryPressure] = [.nominal, .warn, .critical]
        #expect(validPressures.contains(info.memoryPressure))
    }

    // MARK: - BeaconConfig defaults

    @Test("BeaconConfig defaults are privacy-first")
    func configDefaults() {
        let config = BeaconConfig()

        #expect(config.crashReportsEnabled == false)
        #expect(config.diagnosticsEnabled == false)
        #expect(config.reviewBeforeSending == true)
        #expect(config.ingestUrl == "https://beacon.stallari.app/api/v1/reports")
        #expect(!config.deviceId.isEmpty)
    }

    @Test("BeaconConfig deviceIds are unique across instances")
    func configDeviceIdUniqueness() {
        let config1 = BeaconConfig()
        let config2 = BeaconConfig()
        #expect(config1.deviceId != config2.deviceId)
    }

    @Test("BeaconConfig Codable round-trip")
    func configCodableRoundTrip() throws {
        let original = BeaconConfig(
            crashReportsEnabled: true,
            diagnosticsEnabled: true,
            reviewBeforeSending: false,
            ingestUrl: "https://custom.example.com/ingest",
            deviceId: "test-device-id"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(BeaconConfig.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Beacon version

    @Test("Beacon version is 1.2.0")
    func beaconVersion() {
        #expect(BeaconReport.beaconVersion == "1.2.0")
    }

    // MARK: - 1.1.0 fields

    @Test("1.1.0 report Codable round-trip with all new fields")
    func report110CodableRoundTrip() throws {
        let packs = [
            InstalledPack(
                name: "acme-analytics",
                version: "1.2.0",
                installedAt: Date(timeIntervalSinceReferenceDate: 799_000_000),
                installState: .fresh,
                source: .marketplace
            ),
            InstalledPack(
                name: "dev-tools",
                version: "0.3.1",
                installedAt: Date(timeIntervalSinceReferenceDate: 798_000_000),
                installState: .upgraded(from: "0.3.0"),
                source: .dev
            ),
        ]

        let original = BeaconReport(
            reportId: "brpt_v110test",
            type: .crash,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "0.71.2.0", component: "daemon"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .crash(CrashReport(
                type: .signalAbort,
                resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 30.0, subprocessCount: 2, totalManagedRssMb: 200)
            )),
            installId: "ins_a1b2c3d4e5f67890",
            installedPacks: packs,
            activePack: PackRef(name: "acme-analytics", version: "1.2.0"),
            rolloutChannel: "beta"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BeaconReport.self, from: data)

        #expect(decoded.reportId == original.reportId)
        #expect(decoded.installId == "ins_a1b2c3d4e5f67890")
        #expect(decoded.installedPacks == packs)
        #expect(decoded.activePack == PackRef(name: "acme-analytics", version: "1.2.0"))
        #expect(decoded.rolloutChannel == "beta")
        #expect(decoded.payload == original.payload)
    }

    @Test("1.0.0 report deserializes into 1.1.0 struct with nil new fields")
    func legacyReportDecodesCleanly() throws {
        // Simulate a 1.0.0 report JSON — no install_id, installed_packs, active_pack, rollout_channel.
        let json = """
        {
            "beacon_version": "1.0.0",
            "report_id": "brpt_legacy01",
            "type": "diagnostic",
            "timestamp": "2026-03-15T10:00:00Z",
            "app": { "version": "0.44.3.3", "component": "daemon" },
            "system": { "os_version": "15.3.1", "arch": "arm64", "memory_gb": 36, "memory_pressure": "nominal" },
            "payload": {
                "subprocess_count": 3,
                "total_managed_rss_mb": 512,
                "system_memory_pressure": "nominal",
                "dispatch_stats": { "jobs_started": 10, "jobs_succeeded": 9, "jobs_failed": 1, "since": "2026-03-15T09:00:00Z" },
                "mcp_availability": []
            }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BeaconReport.self, from: Data(json.utf8))

        #expect(decoded.reportId == "brpt_legacy01")
        #expect(decoded.type == .diagnostic)
        #expect(decoded.installId == nil)
        #expect(decoded.installedPacks == nil)
        #expect(decoded.activePack == nil)
        #expect(decoded.rolloutChannel == nil)
    }

    @Test("1.1.0 JSON contains new fields when populated")
    func report110JsonContainsNewFields() throws {
        let report = BeaconReport(
            reportId: "brpt_jsonv110",
            type: .feedback,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "1.0.0", component: "app"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .feedback(FeedbackReport(
                message: "Great app!",
                reaction: .loveIt,
                contextScreen: nil,
                includesDiagnosticBundle: false
            )),
            installId: "ins_deadbeefcafebabe",
            activePack: PackRef(name: "acme", version: "1.0.0"),
            rolloutChannel: "stable"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"install_id\""))
        #expect(json.contains("ins_deadbeefcafebabe"))
        #expect(json.contains("\"active_pack\""))
        #expect(json.contains("\"rollout_channel\""))
        #expect(json.contains("\"stable\""))
    }

    @Test("1.1.0 JSON omits new fields when nil")
    func report110JsonOmitsNilFields() throws {
        let report = BeaconReport(
            reportId: "brpt_jsonnil1",
            type: .crash,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "1.0.0", component: "test"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .crash(CrashReport(
                type: .signalAbort,
                resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 30.0, subprocessCount: 2, totalManagedRssMb: 200)
            ))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let json = String(data: data, encoding: .utf8)!

        #expect(!json.contains("install_id"))
        #expect(!json.contains("installed_packs"))
        #expect(!json.contains("active_pack"))
        #expect(!json.contains("rollout_channel"))
    }

    // MARK: - InstalledPack

    @Test("InstalledPack Codable round-trip with all install states")
    func installedPackCodableRoundTrip() throws {
        let packs = [
            InstalledPack(name: "a", version: "1.0.0", installedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), installState: .fresh, source: .marketplace),
            InstalledPack(name: "b", version: "2.0.0", installedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), installState: .upgraded(from: "1.9.0"), source: .sideload),
            InstalledPack(name: "c", version: "3.0.0", installedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), installState: .reinstalled, source: .dev),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(packs)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([InstalledPack].self, from: data)

        #expect(decoded == packs)
    }

    @Test("PackSource raw values match wire format")
    func packSourceRawValues() {
        #expect(PackSource.marketplace.rawValue == "marketplace")
        #expect(PackSource.sideload.rawValue == "sideload")
        #expect(PackSource.dev.rawValue == "dev")
    }

    // MARK: - InstallID

    @Test("InstallID.generate produces valid format")
    func installIdFormat() {
        let id = InstallID.generate()
        #expect(id.hasPrefix("ins_"))
        #expect(id.count == 20)
        #expect(InstallID.isValid(id))
    }

    @Test("InstallID.generate produces unique values")
    func installIdUniqueness() {
        let ids = (0 ..< 100).map { _ in InstallID.generate() }
        let unique = Set(ids)
        #expect(unique.count == 100)
    }

    @Test("InstallID.isValid rejects malformed IDs")
    func installIdValidation() {
        #expect(!InstallID.isValid(""))
        #expect(!InstallID.isValid("ins_"))
        #expect(!InstallID.isValid("ins_short"))
        #expect(!InstallID.isValid("bad_a1b2c3d4e5f67890"))
        #expect(!InstallID.isValid("ins_ZZZZZZZZZZZZZZZZ"))
        #expect(InstallID.isValid("ins_0123456789abcdef"))
    }

    // MARK: - JSON key format

    @Test("JSON uses snake_case keys")
    func jsonSnakeCaseKeys() throws {
        let report = BeaconReport(
            reportId: "brpt_jsontest",
            type: .crash,
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            app: AppInfo(version: "1.0.0", component: "test"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: .crash(CrashReport(
                type: .signalAbort,
                resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 30.0, subprocessCount: 2, totalManagedRssMb: 200)
            ))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("beacon_version"))
        #expect(json.contains("report_id"))
        #expect(json.contains("stack_trace"))
        #expect(json.contains("resource_snapshot"))
        #expect(json.contains("rss_mb"))
        #expect(json.contains("cpu_percent"))
        #expect(json.contains("subprocess_count"))
        #expect(json.contains("total_managed_rss_mb"))
    }
}
