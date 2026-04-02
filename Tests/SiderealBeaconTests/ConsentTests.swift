import Foundation
import Testing

@testable import SiderealBeacon

// MARK: - Consent Tests

@Suite("ConsentGate")
struct ConsentTests {

    // MARK: - Default config (everything off)

    @Test("Default config blocks crash reports")
    func defaultBlocksCrash() {
        let config = BeaconConfig()
        let gate = ConsentGate(config: config)
        #expect(gate.canSendCrashReports() == false)
    }

    @Test("Default config blocks diagnostics")
    func defaultBlocksDiagnostics() {
        let config = BeaconConfig()
        let gate = ConsentGate(config: config)
        #expect(gate.canSendDiagnostics() == false)
    }

    @Test("Feedback is always allowed regardless of config")
    func feedbackAlwaysAllowed() {
        let config = BeaconConfig() // defaults: everything off
        let gate = ConsentGate(config: config)
        #expect(gate.canSendFeedback() == true)
    }

    // MARK: - Enabled config

    @Test("Enabled config allows crash reports")
    func enabledAllowsCrash() {
        let config = BeaconConfig(crashReportsEnabled: true)
        let gate = ConsentGate(config: config)
        #expect(gate.canSendCrashReports() == true)
    }

    @Test("Enabled config allows diagnostics")
    func enabledAllowsDiagnostics() {
        let config = BeaconConfig(diagnosticsEnabled: true)
        let gate = ConsentGate(config: config)
        #expect(gate.canSendDiagnostics() == true)
    }

    // MARK: - check() throws for non-consented types

    @Test("check() throws notConsented for crash report when disabled")
    func checkThrowsForCrash() throws {
        let config = BeaconConfig() // crash disabled
        let gate = ConsentGate(config: config)
        let report = makeReport(type: .crash)

        #expect(throws: SendError.self) {
            try gate.check(report)
        }
    }

    @Test("check() throws notConsented for diagnostic report when disabled")
    func checkThrowsForDiagnostic() throws {
        let config = BeaconConfig() // diagnostics disabled
        let gate = ConsentGate(config: config)
        let report = makeReport(type: .diagnostic)

        #expect(throws: SendError.self) {
            try gate.check(report)
        }
    }

    @Test("check() does not throw for feedback report")
    func checkAllowsFeedback() throws {
        let config = BeaconConfig() // defaults: everything off
        let gate = ConsentGate(config: config)
        let report = makeReport(type: .feedback)

        // Should not throw
        try gate.check(report)
    }

    @Test("check() does not throw for consented crash report")
    func checkAllowsConsentedCrash() throws {
        let config = BeaconConfig(crashReportsEnabled: true)
        let gate = ConsentGate(config: config)
        let report = makeReport(type: .crash)

        try gate.check(report)
    }

    @Test("check() does not throw for consented diagnostic report")
    func checkAllowsConsentedDiagnostic() throws {
        let config = BeaconConfig(diagnosticsEnabled: true)
        let gate = ConsentGate(config: config)
        let report = makeReport(type: .diagnostic)

        try gate.check(report)
    }

    // MARK: - Selective consent

    @Test("Crash enabled but diagnostics disabled")
    func selectiveConsent() {
        let config = BeaconConfig(crashReportsEnabled: true, diagnosticsEnabled: false)
        let gate = ConsentGate(config: config)

        #expect(gate.canSendCrashReports() == true)
        #expect(gate.canSendDiagnostics() == false)
        #expect(gate.canSendFeedback() == true)
    }

    // MARK: - Helpers

    private func makeReport(type: ReportType) -> BeaconReport {
        let payload: ReportPayload
        switch type {
        case .crash:
            payload = .crash(CrashReport(
                type: .signalAbort,
                resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 30.0, subprocessCount: 2, totalManagedRssMb: 200)
            ))
        case .diagnostic:
            payload = .diagnostic(DiagnosticReport(
                subprocessCount: 3,
                totalManagedRssMb: 512,
                systemMemoryPressure: .nominal,
                dispatchStats: DispatchStats(jobsStarted: 5, jobsSucceeded: 4, jobsFailed: 1, since: Date())
            ))
        case .feedback:
            payload = .feedback(FeedbackReport(message: "Test"))
        }

        return BeaconReport(
            type: type,
            app: AppInfo(version: "1.0.0", component: "test"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: payload
        )
    }
}
