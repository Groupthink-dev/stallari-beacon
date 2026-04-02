import Foundation
import Testing

@testable import SiderealBeacon

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
                MCPStatus(name: "sidereal-blade", isAvailable: true),
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
        #expect(config.ingestUrl == "https://beacon.sidereal.cc/api/v1/reports")
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

    @Test("Beacon version is 1.0.0")
    func beaconVersion() {
        #expect(BeaconReport.beaconVersion == "1.0.0")
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
