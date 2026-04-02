import Foundation

/// Checks user consent before allowing report transmission.
///
/// Consent is derived from the ``BeaconConfig`` that the user controls via
/// Settings > Privacy > Beacon. The gate is a pure, synchronous check with
/// no side effects — it never persists state or makes network calls.
///
/// Feedback reports are always allowed because the user explicitly initiated
/// the action (typing text, attaching a screenshot, clicking "Send Feedback").
public struct ConsentGate: Sendable {

    private let config: BeaconConfig

    /// Create a consent gate backed by the given configuration.
    public init(config: BeaconConfig) {
        self.config = config
    }

    /// Whether the user has opted in to sending crash reports.
    public func canSendCrashReports() -> Bool {
        config.crashReportsEnabled
    }

    /// Whether the user has opted in to sending periodic diagnostics.
    public func canSendDiagnostics() -> Bool {
        config.diagnosticsEnabled
    }

    /// Whether feedback can be sent.
    ///
    /// Always returns `true` — feedback is user-initiated and therefore
    /// inherently consented.
    public func canSendFeedback() -> Bool {
        true
    }

    /// Verify that the given report is allowed under the current consent
    /// settings.
    ///
    /// - Throws: ``SendError/notConsented`` if the report type is not
    ///   consented by the user.
    public func check(_ report: BeaconReport) throws {
        switch report.type {
        case .crash:
            guard canSendCrashReports() else { throw SendError.notConsented }
        case .diagnostic:
            guard canSendDiagnostics() else { throw SendError.notConsented }
        case .feedback:
            break // Always allowed.
        }
    }
}
