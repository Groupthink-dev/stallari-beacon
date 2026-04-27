import Foundation
import Testing

@testable import StallariBeacon

@Suite("DiagnosticCollectorHealth")
struct DiagnosticCollectorHealthTests {

    private actor StubGuardian: ProcessGuardianProvider {
        let states: [DaemonHealth]

        init(states: [DaemonHealth] = []) {
            self.states = states
        }

        var subprocessCount: Int { get async { 1 } }
        var totalManagedRssMb: Int { get async { 128 } }
        var mcpStatuses: [MCPStatus] { get async { [] } }
        var dispatchStats: DispatchStats {
            get async {
                DispatchStats(jobsStarted: 0, jobsSucceeded: 0, jobsFailed: 0, since: Date())
            }
        }

        func daemonHealthStates() async -> [DaemonHealth] { states }
    }

    private actor BareGuardian: ProcessGuardianProvider {
        var subprocessCount: Int { get async { 0 } }
        var totalManagedRssMb: Int { get async { 0 } }
        var mcpStatuses: [MCPStatus] { get async { [] } }
        var dispatchStats: DispatchStats {
            get async {
                DispatchStats(jobsStarted: 0, jobsSucceeded: 0, jobsFailed: 0, since: Date())
            }
        }
    }

    private func sampleDaemonHealth(name: String) -> DaemonHealth {
        DaemonHealth(
            name: name,
            restartCount24h: 0,
            restartCount1h: 0,
            recentExitCodes: [],
            heartbeatSkipCount24h: 0,
            circuitBreakerState: "closed",
            circuitBreakerTripCount24h: 0
        )
    }

    @Test("Capture produces a HealthSnapshot when daemonHealthStates is non-empty")
    func testCaptureProducesHealthBlock() async {
        let guardian = StubGuardian(states: [
            sampleDaemonHealth(name: "lens"),
            sampleDaemonHealth(name: "mcp-bridge"),
        ])
        let collector = DiagnosticCollector(guardian: guardian)
        let report = await collector.captureNow()

        #expect(report.health != nil)
        #expect(report.health?.daemons.count == 2)
        #expect(report.health?.daemons.first?.name == "lens")
        #expect(report.health?.daemons.last?.name == "mcp-bridge")
    }

    @Test("Empty daemonHealthStates produces nil health on the report")
    func testEmptyDaemonHealthStatesProducesNilHealth() async {
        let collector = DiagnosticCollector(guardian: BareGuardian())
        let report = await collector.captureNow()

        #expect(report.health == nil)
    }

    @Test("setGuardianProvider swaps the provider for subsequent captures")
    func testSetGuardianProviderSwapsRef() async {
        let initial = BareGuardian()
        let collector = DiagnosticCollector(guardian: initial)
        let firstReport = await collector.captureNow()
        #expect(firstReport.health == nil)

        let replacement = StubGuardian(states: [sampleDaemonHealth(name: "tsidp")])
        await collector.setGuardian(replacement)

        let secondReport = await collector.captureNow()
        #expect(secondReport.health?.daemons.count == 1)
        #expect(secondReport.health?.daemons.first?.name == "tsidp")
    }
}
