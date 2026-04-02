import Foundation
import Testing

@testable import SiderealBeacon

// MARK: - Breadcrumb Tests

@Suite("BreadcrumbTrail")
struct BreadcrumbTests {

    // MARK: - Record and snapshot

    @Test("Record events and snapshot them")
    func recordAndSnapshot() {
        let trail = BreadcrumbTrail(capacity: 10)

        trail.record(event: "app.launch", detail: "cold start")
        trail.record(event: "mcp.start", detail: nil)
        trail.record(event: "dispatch.begin", detail: "daily-digest")

        let crumbs = trail.snapshot()
        #expect(crumbs.count == 3)
        #expect(crumbs[0].event == "app.launch")
        #expect(crumbs[0].detail == "cold start")
        #expect(crumbs[1].event == "mcp.start")
        #expect(crumbs[1].detail == nil)
        #expect(crumbs[2].event == "dispatch.begin")
        #expect(crumbs[2].detail == "daily-digest")
    }

    // MARK: - Ring buffer overflow

    @Test("Ring buffer drops oldest entries when capacity exceeded")
    func ringBufferOverflow() {
        let trail = BreadcrumbTrail(capacity: 3)

        trail.record(event: "a")
        trail.record(event: "b")
        trail.record(event: "c")
        trail.record(event: "d") // Should evict "a"
        trail.record(event: "e") // Should evict "b"

        let crumbs = trail.snapshot()
        #expect(crumbs.count == 3)
        #expect(crumbs[0].event == "c")
        #expect(crumbs[1].event == "d")
        #expect(crumbs[2].event == "e")
    }

    @Test("Ring buffer with capacity 1 retains only the latest event")
    func capacityOne() {
        let trail = BreadcrumbTrail(capacity: 1)

        trail.record(event: "first")
        trail.record(event: "second")
        trail.record(event: "third")

        let crumbs = trail.snapshot()
        #expect(crumbs.count == 1)
        #expect(crumbs[0].event == "third")
    }

    // MARK: - Relative timestamps

    @Test("Relative timestamps are negative for past events")
    func relativeTimestamps() {
        let trail = BreadcrumbTrail(capacity: 10)

        trail.record(event: "past.event")
        // Small delay to ensure the event timestamp is distinctly in the past
        Thread.sleep(forTimeInterval: 0.05)

        let referenceTime = Date()
        let crumbs = trail.snapshot(relativeTo: referenceTime)

        #expect(crumbs.count == 1)
        // The event happened before the reference time, so t should be negative
        #expect(crumbs[0].t < 0)
        // But it should be very recent (within 1 second)
        #expect(crumbs[0].t > -1.0)
    }

    @Test("Relative timestamps are calculated correctly for multiple events")
    func relativeTimestampsMultiple() {
        let trail = BreadcrumbTrail(capacity: 10)

        trail.record(event: "first")
        Thread.sleep(forTimeInterval: 0.05)
        trail.record(event: "second")
        Thread.sleep(forTimeInterval: 0.05)

        let referenceTime = Date()
        let crumbs = trail.snapshot(relativeTo: referenceTime)

        #expect(crumbs.count == 2)
        // First event is further in the past than second
        #expect(crumbs[0].t < crumbs[1].t)
        // Both are negative (before reference)
        #expect(crumbs[0].t < 0)
        #expect(crumbs[1].t < 0)
    }

    // MARK: - Clear

    @Test("Clear removes all breadcrumbs")
    func clearWorks() {
        let trail = BreadcrumbTrail(capacity: 10)

        trail.record(event: "a")
        trail.record(event: "b")
        trail.record(event: "c")

        trail.clear()

        let crumbs = trail.snapshot()
        #expect(crumbs.isEmpty)
    }

    @Test("Clear allows re-recording")
    func clearThenReRecord() {
        let trail = BreadcrumbTrail(capacity: 10)

        trail.record(event: "before")
        trail.clear()
        trail.record(event: "after")

        let crumbs = trail.snapshot()
        #expect(crumbs.count == 1)
        #expect(crumbs[0].event == "after")
    }

    // MARK: - Sorted oldest-first

    @Test("Snapshot is sorted oldest-first")
    func sortedOldestFirst() {
        let trail = BreadcrumbTrail(capacity: 10)

        trail.record(event: "first")
        Thread.sleep(forTimeInterval: 0.01)
        trail.record(event: "second")
        Thread.sleep(forTimeInterval: 0.01)
        trail.record(event: "third")

        let crumbs = trail.snapshot()
        #expect(crumbs.count == 3)
        // Events are oldest-first
        #expect(crumbs[0].event == "first")
        #expect(crumbs[1].event == "second")
        #expect(crumbs[2].event == "third")
        // Timestamps are monotonically increasing (less negative = more recent)
        #expect(crumbs[0].t <= crumbs[1].t)
        #expect(crumbs[1].t <= crumbs[2].t)
    }

    // MARK: - Empty trail

    @Test("Empty trail returns empty snapshot")
    func emptyTrail() {
        let trail = BreadcrumbTrail(capacity: 10)
        let crumbs = trail.snapshot()
        #expect(crumbs.isEmpty)
    }
}
