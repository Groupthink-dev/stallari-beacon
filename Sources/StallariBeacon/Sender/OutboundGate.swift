import Foundation

// MARK: - OutboundDecision

/// The host's verdict on whether the beacon SDK is permitted to flush
/// pending reports to the ingest endpoint.
///
/// The SDK does not own any policy of its own — the host (Stallari harness)
/// reads its user-controlled mode setting and translates it into one of
/// these decisions on each flush. See DD-270 Phase 0 and the harness-side
/// `BeaconOutboundMode` enum for the user-facing semantics.
///
/// Convention #19 (`_shared.md`) constrains outbound network requests to
/// three trigger types — `userInitiated`, `userOptedInDaily`,
/// `userOptedInOnEvent(<event>)`. This gate is the per-flush enforcement
/// surface for that convention on the beacon channel.
public enum OutboundDecision: Sendable, Equatable {
    /// No reports may leave the device on this flush. The caller MUST NOT
    /// touch the network. Pending reports remain in the local audit log.
    ///
    /// This is the verdict for `BeaconOutboundMode.off` and (during
    /// Phase 0) `.manualReview`. The manual-review surface that lets the
    /// user approve individual reports lands in DD-270 Phase E; until then
    /// `.manualReview` behaves identically to `.off` from the SDK's view.
    case suppressed

    /// Only reports whose payload is a crash may be sent on this flush.
    /// Verdict for `BeaconOutboundMode.autoSendOnCrash`.
    case crashOnly

    /// All consented report types may be sent. Verdict for
    /// `BeaconOutboundMode.dailyBatch` (the existing periodic flush is
    /// further constrained to once-per-24h by the host scheduler — that
    /// scheduler lives in the harness, not in the SDK).
    case permitted
}

// MARK: - OutboundGate typealias

/// Closure injected at SDK init that returns the current outbound decision.
///
/// The closure is invoked once per call to `ReportSender.sendableReports()`
/// (and therefore once per `sendAllPending()` call). Implementations are
/// expected to read a user-controlled setting and translate it into a
/// decision; they MUST NOT make blocking I/O calls or take long enough that
/// flush latency suffers.
///
/// A `nil` gate is **fail-closed** (AUD-05-05 / CONV-19): the SDK treats
/// every flush as `.suppressed` and nothing leaves the device. A consumer
/// that wants outbound traffic MUST wire an explicit gate returning its
/// consented verdict. (Before DD-397 Phase C a `nil` gate defaulted to
/// `.permitted`, which let an external SDK consumer phone home unconsented
/// merely by forgetting to wire the gate.)
public typealias OutboundGate = @Sendable () async -> OutboundDecision
