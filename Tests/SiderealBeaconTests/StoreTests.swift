import Foundation
import Testing

@testable import SiderealBeacon

// MARK: - Store Tests

@Suite("ReportStore")
struct StoreTests {

    /// Creates a temp directory for test isolation and returns the store and cleanup closure.
    private func makeStore() -> (store: ReportStore, cleanup: @Sendable () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sidereal-beacon-tests-\(UUID().uuidString)")
        let store = ReportStore(baseDirectory: tempDir)
        let cleanup: @Sendable () -> Void = {
            try? FileManager.default.removeItem(at: tempDir)
        }
        return (store, cleanup)
    }

    private func makeReport(
        id: String? = nil,
        type: ReportType = .crash,
        timestamp: Date = Date()
    ) -> BeaconReport {
        let payload: ReportPayload
        switch type {
        case .crash:
            payload = .crash(CrashReport(
                type: .signalAbort,
                signal: "SIGABRT",
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
            payload = .feedback(FeedbackReport(message: "Test feedback", reaction: .works))
        }

        return BeaconReport(
            reportId: id,
            type: type,
            timestamp: timestamp,
            app: AppInfo(version: "1.0.0", component: "test"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: payload
        )
    }

    // MARK: - Save and retrieve

    @Test("Save and retrieve a report")
    func saveAndRetrieve() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let report = makeReport(id: "brpt_aabbccdd")
        try await store.save(report)

        let retrieved = try await store.get("brpt_aabbccdd")
        #expect(retrieved != nil)
        #expect(retrieved?.reportId == "brpt_aabbccdd")
        #expect(retrieved?.type == .crash)
    }

    // MARK: - List pending sorted by date descending

    @Test("List pending reports sorted newest first")
    func listPendingSorted() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let older = makeReport(id: "brpt_older000", timestamp: Date(timeIntervalSinceNow: -60))
        let newer = makeReport(id: "brpt_newer000", timestamp: Date(timeIntervalSinceNow: -10))
        let newest = makeReport(id: "brpt_newest00", timestamp: Date())

        try await store.save(older)
        try await store.save(newer)
        try await store.save(newest)

        let pending = try await store.listPending()
        #expect(pending.count == 3)
        #expect(pending[0].reportId == "brpt_newest00")
        #expect(pending[1].reportId == "brpt_newer000")
        #expect(pending[2].reportId == "brpt_older000")
    }

    // MARK: - Mark as sent

    @Test("Mark as sent moves report from pending to sent")
    func markAsSent() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let report = makeReport(id: "brpt_senttest")
        try await store.save(report)

        // Verify it's pending
        let pendingBefore = try await store.listPending()
        #expect(pendingBefore.count == 1)

        // Mark as sent
        try await store.markSent("brpt_senttest")

        // No longer pending
        let pendingAfter = try await store.listPending()
        #expect(pendingAfter.count == 0)

        // Now in sent
        let sent = try await store.listSent()
        #expect(sent.count == 1)
        #expect(sent[0].reportId == "brpt_senttest")

        // Still retrievable by ID
        let retrieved = try await store.get("brpt_senttest")
        #expect(retrieved != nil)
    }

    // MARK: - Delete

    @Test("Delete a report from pending")
    func deleteFromPending() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let report = makeReport(id: "brpt_delete00")
        try await store.save(report)

        try await store.delete("brpt_delete00")

        let retrieved = try await store.get("brpt_delete00")
        #expect(retrieved == nil)
    }

    @Test("Delete a report from sent")
    func deleteFromSent() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let report = makeReport(id: "brpt_delsent0")
        try await store.save(report)
        try await store.markSent("brpt_delsent0")

        try await store.delete("brpt_delsent0")

        let retrieved = try await store.get("brpt_delsent0")
        #expect(retrieved == nil)
    }

    @Test("Delete nonexistent report throws reportNotFound")
    func deleteNonexistent() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        do {
            try await store.delete("brpt_nonexist")
            Issue.record("Should have thrown")
        } catch let error as ReportStoreError {
            guard case .reportNotFound(let id) = error else {
                Issue.record("Expected reportNotFound, got \(error)")
                return
            }
            #expect(id == "brpt_nonexist")
        }
    }

    // MARK: - Prune old sent reports

    @Test("Prune old sent reports removes only expired ones")
    func pruneOldSent() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        // Create an old report (31 days ago)
        let old = makeReport(id: "brpt_old00000", timestamp: Date(timeIntervalSinceNow: -31 * 86400))
        try await store.save(old)
        try await store.markSent("brpt_old00000")

        // Create a recent report (1 day ago)
        let recent = makeReport(id: "brpt_recent00", timestamp: Date(timeIntervalSinceNow: -1 * 86400))
        try await store.save(recent)
        try await store.markSent("brpt_recent00")

        let pruned = try await store.pruneSent(olderThan: 30)
        #expect(pruned == 1)

        // Recent report still exists
        let remaining = try await store.listSent()
        #expect(remaining.count == 1)
        #expect(remaining[0].reportId == "brpt_recent00")
    }

    // MARK: - Delete all

    @Test("Delete all removes everything")
    func deleteAll() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        try await store.save(makeReport(id: "brpt_all00001"))
        try await store.save(makeReport(id: "brpt_all00002"))
        try await store.save(makeReport(id: "brpt_all00003"))
        try await store.markSent("brpt_all00003")

        try await store.deleteAll()

        let pending = try await store.listPending()
        let sent = try await store.listSent()
        #expect(pending.count == 0)
        #expect(sent.count == 0)
    }

    // MARK: - Pending count

    @Test("Pending count matches actual pending reports")
    func pendingCount() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        #expect(try await store.pendingCount() == 0)

        try await store.save(makeReport(id: "brpt_count001"))
        try await store.save(makeReport(id: "brpt_count002"))
        #expect(try await store.pendingCount() == 2)

        try await store.markSent("brpt_count001")
        #expect(try await store.pendingCount() == 1)
    }

    // MARK: - Empty store

    @Test("Empty store returns empty lists and zero count")
    func emptyStore() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let pending = try await store.listPending()
        let sent = try await store.listSent()
        let count = try await store.pendingCount()

        #expect(pending.isEmpty)
        #expect(sent.isEmpty)
        #expect(count == 0)
    }
}
