// DD-270 Phase 0 — convention #19 outbound gate.
// Verifies that ``ReportSender`` honours the host-supplied ``OutboundGate``
// closure: `.suppressed` means no flush ever happens, `.crashOnly` filters
// the pending list to crash payloads, `.permitted` (or no gate wired)
// preserves the legacy behaviour. The gate verdict is exercised through
// the public ``sendableReports()`` chokepoint so URLSession never has to
// be mocked — the absence of a flush is observable from the SendResult and
// the unchanged store state.

import Foundation
import Testing

@testable import StallariBeacon

@Suite("ReportSender outbound gate (DD-270 Phase 0)")
struct SenderGateTests {

    // MARK: - Fixture helpers

    private func makeStore() -> (store: ReportStore, cleanup: @Sendable () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fabric-nerve-gate-tests-\(UUID().uuidString)")
        let store = FileReportStore(baseDirectory: tempDir)
        let cleanup: @Sendable () -> Void = {
            try? FileManager.default.removeItem(at: tempDir)
        }
        return (store, cleanup)
    }

    private func makeConfig() -> BeaconConfig {
        // crash + diagnostics enabled so the legacy ConsentGate doesn't
        // mask the outbound gate's behaviour. Feedback is always allowed.
        BeaconConfig(crashReportsEnabled: true, diagnosticsEnabled: true)
    }

    private func makeReport(_ type: ReportType, id: String) -> BeaconReport {
        let payload: ReportPayload
        switch type {
        case .crash:
            payload = .crash(CrashReport(
                type: .signalAbort,
                signal: "SIGABRT",
                resourceSnapshot: ResourceSnapshot(
                    rssMb: 100, cpuPercent: 30.0,
                    subprocessCount: 2, totalManagedRssMb: 200
                )
            ))
        case .diagnostic:
            payload = .diagnostic(DiagnosticReport(
                subprocessCount: 3, totalManagedRssMb: 512,
                systemMemoryPressure: .nominal,
                dispatchStats: DispatchStats(
                    jobsStarted: 5, jobsSucceeded: 4, jobsFailed: 1, since: Date()
                )
            ))
        case .feedback:
            payload = .feedback(FeedbackReport(message: "hello"))
        case .security:
            payload = .security(SecurityReport(
                eventType: .guardrailHashMismatch,
                detail: "test",
                baselineVersion: "1.0.0"
            ))
        }
        return BeaconReport(
            reportId: id,
            type: type,
            app: AppInfo(version: "1.0.0", component: "test"),
            system: SystemInfo(
                osVersion: "15.3.1", arch: "arm64",
                memoryGb: 36, memoryPressure: .nominal
            ),
            payload: payload
        )
    }

    // MARK: - Tests

    /// `.suppressed` returns no sendable reports and `sendAllPending`
    /// returns an empty SendResult without ever entering the send loop.
    /// The store still holds every queued report — outbound is fully
    /// inert.
    @Test("Sender refuses flush when gate suppresses")
    func senderRefusesFlushWhenGateSuppresses() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        // Queue 5 reports of mixed types.
        for i in 0..<3 {
            try await store.save(makeReport(.crash, id: "crash-\(i)"))
        }
        for i in 0..<2 {
            try await store.save(makeReport(.diagnostic, id: "diag-\(i)"))
        }

        let gate: OutboundGate = { .suppressed }
        let sender = ReportSender(
            config: makeConfig(),
            store: store,
            outboundGate: gate
        )

        // Phase 0 chokepoint — gate filters before listPending lookup.
        let sendable = try await sender.sendableReports()
        #expect(sendable.isEmpty)

        // sendAllPending() returns an empty SendResult without touching
        // the network or the store loop.
        let result = try await sender.sendAllPending()
        #expect(result.sent == 0)
        #expect(result.failed == 0)
        #expect(result.errors.isEmpty)

        // All 5 reports remain in the pending queue — no flush happened.
        let pending = try await store.listPending()
        #expect(pending.count == 5)
    }

    /// An explicit `.permitted` gate returns the full pending list — the
    /// gate is fully transparent. We don't drive `sendAllPending()` here
    /// because the URL session would attempt real I/O against an
    /// unreachable host; testing `sendableReports()` is the canonical
    /// chokepoint exercise.
    @Test("Sender proceeds when gate permits")
    func senderProceedsWhenGatePermits() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try await store.save(makeReport(.crash, id: "c-1"))
        try await store.save(makeReport(.diagnostic, id: "d-1"))
        try await store.save(makeReport(.feedback, id: "f-1"))

        let gate: OutboundGate = { .permitted }
        let sender = ReportSender(
            config: makeConfig(),
            store: store,
            outboundGate: gate
        )

        let sendable = try await sender.sendableReports()
        #expect(sendable.count == 3)
        let ids = Set(sendable.map(\.reportId))
        #expect(ids == ["c-1", "d-1", "f-1"])
    }

    /// AUD-05-05 / CONV-19 — a `nil` gate is **fail-closed**: a sender wired
    /// without an explicit ``OutboundGate`` suppresses every flush and never
    /// touches the network, even for reports the legacy ``ConsentGate`` would
    /// always allow (`.feedback`, `.security`). Before DD-397 Phase C the
    /// default was `.permitted`, which let an external SDK consumer phone
    /// home unconsented merely by forgetting to wire the gate.
    @Test("No gate wired is fail-closed (suppressed)")
    func noGateWiredIsFailClosed() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try await store.save(makeReport(.crash, id: "c-1"))
        try await store.save(makeReport(.diagnostic, id: "d-1"))
        try await store.save(makeReport(.feedback, id: "f-1"))
        try await store.save(makeReport(.security, id: "s-1"))

        // No outboundGate — the SDK default.
        let sender = ReportSender(config: makeConfig(), store: store)

        let sendable = try await sender.sendableReports()
        #expect(sendable.isEmpty)

        let result = try await sender.sendAllPending()
        #expect(result.sent == 0)
        #expect(result.failed == 0)
        #expect(result.errors.isEmpty)

        // Nothing left the device — all four reports remain pending.
        let pending = try await store.listPending()
        #expect(pending.count == 4)
    }

    /// `.crashOnly` filters the pending list to `.crash` payloads. The
    /// non-crash reports remain in the store; the gate doesn't drop them,
    /// it just defers them until the user's mode permits other types.
    @Test("Crash-only gate filters by payload type")
    func crashOnlyGateFiltersByPayload() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try await store.save(makeReport(.crash, id: "crash-A"))
        try await store.save(makeReport(.diagnostic, id: "diag-A"))
        try await store.save(makeReport(.feedback, id: "fb-A"))
        try await store.save(makeReport(.crash, id: "crash-B"))
        try await store.save(makeReport(.security, id: "sec-A"))

        let gate: OutboundGate = { .crashOnly }
        let sender = ReportSender(
            config: makeConfig(),
            store: store,
            outboundGate: gate
        )

        let sendable = try await sender.sendableReports()
        #expect(sendable.count == 2)
        let ids = Set(sendable.map(\.reportId))
        #expect(ids == ["crash-A", "crash-B"])
        #expect(sendable.allSatisfy { $0.type == .crash })
    }
}
