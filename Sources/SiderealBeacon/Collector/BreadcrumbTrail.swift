import Foundation
import os

// MARK: - BreadcrumbTrail

/// A ring buffer of recent events leading up to a crash or diagnostic capture.
///
/// Thread-safe via `os_unfair_lock` rather than `NSLock` or Swift concurrency
/// primitives. This is deliberate: `os_unfair_lock` is async-signal-safe, which
/// means the lock can be safely acquired from a POSIX signal handler context
/// during crash collection. Higher-level locks (NSLock, dispatch queues, actors)
/// allocate or make ObjC calls that are forbidden in signal handlers.
///
/// Timestamps are stored as absolute `Date` values internally and converted to
/// relative `TimeInterval` offsets only when a snapshot is taken. This avoids
/// clock drift issues if the system clock changes between recording and capture.
public final class BreadcrumbTrail: @unchecked Sendable {

    // MARK: - Internal storage entry

    /// Internal timestamped breadcrumb — stores the absolute time of recording.
    private struct Entry {
        let timestamp: Date
        let event: String
        let detail: String?
    }

    // MARK: - Properties

    private let capacity: Int

    /// Ring buffer backing storage. Pre-allocated to `capacity`.
    private var buffer: [Entry?]

    /// Write index into the ring buffer (wraps at `capacity`).
    private var writeIndex: Int = 0

    /// Total number of entries recorded (may exceed capacity; used to determine
    /// whether the buffer has wrapped).
    private var totalRecorded: Int = 0

    /// Low-level lock. Allocated on the heap to satisfy the "must not be moved
    /// after first use" requirement of `os_unfair_lock`.
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    // MARK: - Init / Deinit

    /// Creates a breadcrumb trail with a fixed ring buffer capacity.
    ///
    /// - Parameter capacity: Maximum number of breadcrumbs retained. Oldest
    ///   entries are silently discarded when the buffer is full. Defaults to 50.
    public init(capacity: Int = 50) {
        precondition(capacity > 0, "BreadcrumbTrail capacity must be positive")
        self.capacity = capacity
        self.buffer = [Entry?](repeating: nil, count: capacity)
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    // MARK: - Public API

    /// Record an event with the current timestamp.
    ///
    /// This method is safe to call from any thread, including concurrent queues.
    ///
    /// - Parameters:
    ///   - event: Short event identifier (e.g. "mcp.start", "dispatch.begin").
    ///   - detail: Optional human-readable detail string.
    public func record(event: String, detail: String? = nil) {
        let entry = Entry(timestamp: Date(), event: event, detail: detail)
        os_unfair_lock_lock(lock)
        buffer[writeIndex] = entry
        writeIndex = (writeIndex + 1) % capacity
        totalRecorded += 1
        os_unfair_lock_unlock(lock)
    }

    /// Returns a snapshot of all recorded breadcrumbs with timestamps
    /// recalculated as offsets relative to the given date.
    ///
    /// Breadcrumbs are returned sorted oldest-first. The `t` field on each
    /// ``Breadcrumb`` is negative for events that occurred before `relativeTo`
    /// and positive for events after (the latter is unusual but possible if
    /// `relativeTo` is in the past).
    ///
    /// - Parameter relativeTo: The reference point for calculating relative
    ///   timestamps. Defaults to `Date()` (now).
    /// - Returns: Array of breadcrumbs sorted oldest-first.
    public func snapshot(relativeTo: Date = Date()) -> [Breadcrumb] {
        os_unfair_lock_lock(lock)
        let entries = copyEntries()
        os_unfair_lock_unlock(lock)

        let reference = relativeTo.timeIntervalSinceReferenceDate
        return entries.map { entry in
            let t = entry.timestamp.timeIntervalSinceReferenceDate - reference
            return Breadcrumb(t: t, event: entry.event, detail: entry.detail)
        }
    }

    /// Removes all recorded breadcrumbs.
    public func clear() {
        os_unfair_lock_lock(lock)
        for i in 0 ..< capacity {
            buffer[i] = nil
        }
        writeIndex = 0
        totalRecorded = 0
        os_unfair_lock_unlock(lock)
    }

    // MARK: - Private helpers

    /// Copies non-nil entries out of the ring buffer in chronological order.
    ///
    /// Must be called while holding `lock`.
    private func copyEntries() -> [Entry] {
        let count = min(totalRecorded, capacity)
        guard count > 0 else { return [] }

        var result = [Entry]()
        result.reserveCapacity(count)

        // If we haven't wrapped, entries are 0 ..< writeIndex.
        // If we have wrapped, the oldest entry is at writeIndex (the next to be
        // overwritten), and we read writeIndex ..< capacity, then 0 ..< writeIndex.
        let start = totalRecorded >= capacity ? writeIndex : 0
        for i in 0 ..< count {
            let index = (start + i) % capacity
            if let entry = buffer[index] {
                result.append(entry)
            }
        }

        return result
    }
}
