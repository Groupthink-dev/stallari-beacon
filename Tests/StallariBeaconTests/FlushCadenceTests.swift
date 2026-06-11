// DD-397 Phase C / AUD-05-04 — convention #19 "dailyBatch" cadence.
// The periodic flush loop used to sleep 5 minutes forever (288 unsolicited
// flush attempts a day), contradicting both the `BeaconOutboundMode.dailyBatch`
// semantics and convention #19's no-chatty-phone-home posture. The cadence is
// now a 24h default, injectable for tests/hosts. We assert the contract through
// the public ``Beacon/flushIntervalSeconds`` accessor rather than driving the
// live loop, which would install process-wide crash signal handlers.

import Foundation
import Testing

@testable import StallariBeacon

@Suite("Beacon flush cadence (DD-397 Phase C / AUD-05-04)")
struct FlushCadenceTests {

    private func makeBeacon(flushInterval: TimeInterval? = nil) -> Beacon {
        let config = BeaconConfig()
        let app = AppInfo(version: "1.0.0", component: "test")
        let store = FileReportStore(
            baseDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("flush-cadence-\(UUID().uuidString)")
        )
        if let flushInterval {
            return Beacon(config: config, appInfo: app, store: store, flushInterval: flushInterval)
        }
        return Beacon(config: config, appInfo: app, store: store)
    }

    /// The default cadence is daily (86400s) — not the old 5-minute loop.
    @Test("Default flush cadence is 24h")
    func defaultCadenceIsDaily() async {
        let beacon = makeBeacon()
        #expect(await beacon.flushIntervalSeconds == 24 * 60 * 60)
        // Guard against the regression specifically: never the old 5 min.
        #expect(await beacon.flushIntervalSeconds != 5 * 60)
    }

    /// An injected cadence is honoured (host override / test seam).
    @Test("Injected flush cadence is honoured")
    func injectedCadenceIsHonoured() async {
        let beacon = makeBeacon(flushInterval: 3600)
        #expect(await beacon.flushIntervalSeconds == 3600)
    }
}
