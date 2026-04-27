import Foundation
import Testing

@testable import StallariBeacon

@Suite("HealthSnapshotEncoding")
struct HealthSnapshotEncodingTests {

    private func makeFullyPopulatedSnapshot() -> HealthSnapshot {
        let lens = DaemonHealth(
            name: "lens",
            restartCount24h: 12,
            restartCount1h: 4,
            lastExitCode: 1,
            lastExitSignal: "SIGABRT",
            recentExitCodes: [1, 1, 1, 1, 0, 1, 1, 1],
            heartbeatSkipCount24h: 3,
            heartbeatStaleSeconds: 45,
            circuitBreakerState: "open",
            circuitBreakerTripCount24h: 2,
            lastTracebackSignature: "9f2c1a04abcd1234",
            lastTracebackExceptionClass: "sqlcipher3.dbapi2.OperationalError",
            stableRunSeconds: 30
        )
        let mcp = DaemonHealth(
            name: "mcp-bridge",
            restartCount24h: 0,
            restartCount1h: 0,
            lastExitCode: 0,
            lastExitSignal: nil,
            recentExitCodes: [],
            heartbeatSkipCount24h: 0,
            heartbeatStaleSeconds: nil,
            circuitBreakerState: "closed",
            circuitBreakerTripCount24h: 0,
            lastTracebackSignature: nil,
            lastTracebackExceptionClass: nil,
            stableRunSeconds: 86400
        )
        return HealthSnapshot(
            snapshotAt: Date(timeIntervalSince1970: 1_714_186_800),
            daemons: [lens, mcp],
            lensLockContentionRate: 0.07,
            healthLoopTickRate: 1.0
        )
    }

    @Test("Round-trip with fully populated HealthSnapshot")
    func testRoundtripFullyPopulated() throws {
        let snapshot = makeFullyPopulatedSnapshot()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test("Round-trip with nil optionals omits keys and decodes back as nil")
    func testRoundtripWithNilOptionals() throws {
        let daemon = DaemonHealth(
            name: "tsidp",
            restartCount24h: 1,
            restartCount1h: 0,
            lastExitCode: nil,
            lastExitSignal: nil,
            recentExitCodes: [0],
            heartbeatSkipCount24h: 0,
            heartbeatStaleSeconds: nil,
            circuitBreakerState: "closed",
            circuitBreakerTripCount24h: 0,
            lastTracebackSignature: nil,
            lastTracebackExceptionClass: nil,
            stableRunSeconds: nil
        )
        let snapshot = HealthSnapshot(
            snapshotAt: Date(timeIntervalSince1970: 1_714_186_800),
            daemons: [daemon],
            lensLockContentionRate: nil,
            healthLoopTickRate: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["lens_lock_contention_rate"] == nil)
        #expect(json["health_loop_tick_rate"] == nil)
        let daemons = try #require(json["daemons"] as? [[String: Any]])
        let first = try #require(daemons.first)
        #expect(first["last_exit_code"] == nil)
        #expect(first["last_exit_signal"] == nil)
        #expect(first["heartbeat_stale_seconds"] == nil)
        #expect(first["last_traceback_signature"] == nil)
        #expect(first["last_traceback_exception_class"] == nil)
        #expect(first["stable_run_seconds"] == nil)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HealthSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.lensLockContentionRate == nil)
        #expect(decoded.healthLoopTickRate == nil)
        let decodedDaemon = try #require(decoded.daemons.first)
        #expect(decodedDaemon.lastExitCode == nil)
        #expect(decodedDaemon.lastExitSignal == nil)
        #expect(decodedDaemon.heartbeatStaleSeconds == nil)
        #expect(decodedDaemon.lastTracebackSignature == nil)
        #expect(decodedDaemon.lastTracebackExceptionClass == nil)
        #expect(decodedDaemon.stableRunSeconds == nil)
    }

    @Test("DiagnosticReport without health key decodes with health == nil")
    func testDiagnosticReport110BackwardsCompat() throws {
        let json = """
        {
          "subprocess_count": 3,
          "total_managed_rss_mb": 256,
          "system_memory_pressure": "nominal",
          "dispatch_stats": {
            "jobs_started": 10,
            "jobs_succeeded": 9,
            "jobs_failed": 1,
            "since": "2026-04-27T00:00:00Z"
          },
          "mcp_availability": []
        }
        """

        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(DiagnosticReport.self, from: data)

        #expect(report.health == nil)
        #expect(report.subprocessCount == 3)
        #expect(report.totalManagedRssMb == 256)
        #expect(report.dispatchStats.jobsStarted == 10)
    }

    @Test("BeaconReport.beaconVersion is 1.2.0")
    func testBeaconVersionConstant() {
        #expect(BeaconReport.beaconVersion == "1.2.0")
    }
}
