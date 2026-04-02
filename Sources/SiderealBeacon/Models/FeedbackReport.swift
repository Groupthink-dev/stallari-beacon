import Foundation

// MARK: - ReactionType

/// Quick-reaction sentiment from the user.
public enum ReactionType: String, Codable, Sendable {
    case works
    case broken
    case confused
    case loveIt = "love_it"
}

// MARK: - FeedbackReport

/// User feedback payload, optionally bundled with a diagnostic snapshot.
public struct FeedbackReport: Codable, Sendable, Equatable {
    /// Free-text message from the user.
    public let message: String

    /// Optional quick-reaction sentiment.
    public let reaction: ReactionType?

    /// The screen or view the user was on when they submitted feedback.
    public let contextScreen: String?

    /// Whether a full diagnostic bundle is attached alongside this feedback.
    public let includesDiagnosticBundle: Bool

    public init(
        message: String,
        reaction: ReactionType? = nil,
        contextScreen: String? = nil,
        includesDiagnosticBundle: Bool = false
    ) {
        self.message = message
        self.reaction = reaction
        self.contextScreen = contextScreen
        self.includesDiagnosticBundle = includesDiagnosticBundle
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case reaction
        case contextScreen = "context_screen"
        case includesDiagnosticBundle = "includes_diagnostic_bundle"
    }
}
