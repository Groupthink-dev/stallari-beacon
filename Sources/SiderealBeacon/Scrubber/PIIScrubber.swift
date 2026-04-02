import Foundation

// MARK: - PIIScrubber

/// Strips personally-identifiable information from beacon reports before they
/// touch disk.
///
/// The scrubber is **aggressively conservative**: when a string could plausibly
/// contain PII, it is redacted. False positives (over-redaction) are acceptable;
/// false negatives (leaked PII) are not.
///
/// ## Usage
///
/// ```swift
/// let scrubber = PIIScrubber()
/// let cleanReport = scrubber.scrub(rawReport)
/// ```
///
/// Custom patterns can be injected at init for app-specific redaction:
///
/// ```swift
/// let scrubber = PIIScrubber(customPatterns: [
///     (pattern: #"vault_id=[A-Za-z0-9]+"#, replacement: "vault_id=[REDACTED]")
/// ])
/// ```
public struct PIIScrubber: Sendable {

    /// All compiled patterns applied in order during scrubbing.
    private let patterns: [ScrubberPattern]

    // MARK: - Init

    /// Creates a scrubber with the default patterns plus optional app-specific ones.
    ///
    /// Custom patterns are appended after the defaults, so they run last.
    ///
    /// - Parameter customPatterns: Additional `(pattern, replacement)` pairs.
    ///   The pattern string is compiled as an `NSRegularExpression`. Invalid
    ///   patterns are silently skipped (logged in debug builds).
    public init(customPatterns: [(pattern: String, replacement: String)] = []) {
        var compiled = ScrubberPatterns.defaults

        for custom in customPatterns {
            guard let regex = try? NSRegularExpression(pattern: custom.pattern, options: []) else {
                #if DEBUG
                print("[PIIScrubber] Invalid custom pattern: \(custom.pattern)")
                #endif
                continue
            }
            compiled.append(ScrubberPattern(regex: regex, replacement: custom.replacement))
        }

        self.patterns = compiled
    }

    // MARK: - Report scrubbing

    /// Returns a copy of the report with all string fields scrubbed of PII.
    ///
    /// **What is preserved (no scrubbing):**
    /// - Report ID (intentional identifier)
    /// - Timestamp (no user data)
    /// - App info (version + component are controlled vocabulary)
    /// - System info (OS version, arch, memory — no user data)
    /// - Crash type, signal, jetsam reason (controlled vocabulary)
    /// - Resource snapshot (purely numeric)
    /// - Breadcrumb event names (controlled vocabulary)
    /// - Diagnostic numeric fields and MCP server names (controlled vocabulary)
    ///
    /// **What is scrubbed:**
    /// - Stack trace frame strings (may embed file paths with usernames)
    /// - Breadcrumb detail strings (may contain arbitrary context)
    /// - Feedback message text (user-authored free text)
    /// - Feedback context screen (may contain path-like identifiers)
    public func scrub(_ report: BeaconReport) -> BeaconReport {
        let scrubbedPayload: ReportPayload = switch report.payload {
        case .crash(let crash):
            .crash(scrubCrashReport(crash))
        case .diagnostic(let diagnostic):
            .diagnostic(diagnostic) // Numeric fields + controlled vocabulary — no PII
        case .feedback(let feedback):
            .feedback(scrubFeedbackReport(feedback))
        }

        return BeaconReport(
            reportId: report.reportId,
            type: report.type,
            timestamp: report.timestamp,
            app: report.app,
            system: report.system,
            payload: scrubbedPayload
        )
    }

    // MARK: - String scrubbing

    /// Scrubs a single string of all PII patterns.
    ///
    /// Applies every pattern in order. Useful for ad-hoc string scrubbing
    /// outside of structured reports (e.g. log lines, error messages).
    public func scrub(_ string: String) -> String {
        applyPatterns(to: string)
    }

    // MARK: - Payload scrubbing

    /// Scrubs a crash report's stack trace frames and breadcrumb details.
    private func scrubCrashReport(_ crash: CrashReport) -> CrashReport {
        CrashReport(
            type: crash.type,
            signal: crash.signal,
            jetsamReason: crash.jetsamReason,
            resourceSnapshot: crash.resourceSnapshot,
            breadcrumbs: scrubBreadcrumbs(crash.breadcrumbs),
            stackTrace: scrubStackTrace(crash.stackTrace)
        )
    }

    /// Scrubs a feedback report's user-authored text fields.
    private func scrubFeedbackReport(_ feedback: FeedbackReport) -> FeedbackReport {
        FeedbackReport(
            message: applyPatterns(to: feedback.message),
            reaction: feedback.reaction,
            contextScreen: feedback.contextScreen.map { applyPatterns(to: $0) },
            includesDiagnosticBundle: feedback.includesDiagnosticBundle
        )
    }

    /// Scrubs breadcrumb detail strings while preserving the event name
    /// (events are controlled vocabulary, not user content).
    private func scrubBreadcrumbs(_ breadcrumbs: [Breadcrumb]) -> [Breadcrumb] {
        breadcrumbs.map { crumb in
            Breadcrumb(
                t: crumb.t,
                event: crumb.event,
                detail: crumb.detail.map { applyPatterns(to: $0) }
            )
        }
    }

    /// Scrubs stack trace frames.
    ///
    /// Stack traces contain valuable debugging info (module + function names)
    /// but may also embed file paths with usernames. Each frame string is
    /// scrubbed through the full pattern set.
    private func scrubStackTrace(_ frames: [String]) -> [String] {
        frames.map { applyPatterns(to: $0) }
    }

    // MARK: - Pattern engine

    /// Applies all compiled patterns sequentially to a string.
    ///
    /// Each pattern's replacement may use capture group references (e.g. `$1`)
    /// for patterns like `homePath` that preserve structural context.
    private func applyPatterns(to input: String) -> String {
        var result = input

        for pattern in patterns {
            // Re-compute range each iteration since replacements change string length.
            let currentRange = NSRange(result.startIndex..., in: result)
            result = pattern.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: currentRange,
                withTemplate: pattern.replacement
            )
        }

        return result
    }
}
