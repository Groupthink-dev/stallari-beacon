import Foundation

// MARK: - FeedbackCollector

/// Collects user-initiated feedback and packages it as ``FeedbackReport`` instances.
///
/// Feedback is inherently user-driven — the user taps a "Send Feedback" button,
/// optionally selects a reaction emoji, and types a message. This actor provides
/// a clean interface for creating report instances with attached context
/// (current screen, app version, optional diagnostic bundle flag).
public actor FeedbackCollector {

    // MARK: - Init

    /// Creates a feedback collector.
    public init() {}

    // MARK: - Public API

    /// Creates a feedback report from user input.
    ///
    /// The returned ``FeedbackReport`` is ready to be wrapped in a
    /// ``BeaconReport`` envelope and routed through the scrub/store/send
    /// pipeline.
    ///
    /// - Parameters:
    ///   - message: Free-text feedback message from the user.
    ///   - reaction: Optional quick-reaction sentiment (e.g. `.works`, `.broken`).
    ///   - contextScreen: The screen or view the user was on when submitting.
    ///     Pass `nil` if not determinable.
    ///   - includeDiagnostics: Whether a full diagnostic bundle should be
    ///     attached alongside this feedback. When `true`, the Beacon
    ///     orchestrator captures a ``DiagnosticReport`` and bundles it with
    ///     the feedback envelope.
    /// - Returns: A populated ``FeedbackReport``.
    public func createFeedback(
        message: String,
        reaction: ReactionType? = nil,
        contextScreen: String? = nil,
        includeDiagnostics: Bool = false
    ) -> FeedbackReport {
        FeedbackReport(
            message: message,
            reaction: reaction,
            contextScreen: contextScreen,
            includesDiagnosticBundle: includeDiagnostics
        )
    }
}
