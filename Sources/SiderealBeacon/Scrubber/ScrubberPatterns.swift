import Foundation

// MARK: - ScrubberPattern

/// A compiled regex paired with its replacement string.
public struct ScrubberPattern: Sendable {
    public let regex: NSRegularExpression
    public let replacement: String

    public init(regex: NSRegularExpression, replacement: String) {
        self.regex = regex
        self.replacement = replacement
    }
}

// MARK: - ScrubberPatterns

/// Default PII-detection patterns for the ``PIIScrubber``.
///
/// Each pattern is a compiled `NSRegularExpression` paired with a replacement
/// string. Patterns are applied in order — more specific patterns (e.g.
/// `envVarSecret`) should come before broader ones (e.g. `apiKeyValue`) to
/// avoid partial matches.
///
/// All patterns are auditable in this single file.
public enum ScrubberPatterns {

    // MARK: - Email

    /// RFC-lite email address detection.
    public static let email = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
            options: []
        ),
        replacement: "[EMAIL]"
    )

    // MARK: - File paths

    /// macOS/Linux home directory paths: `/Users/<username>/` or `/home/<username>/`.
    /// Replaces the username component while preserving the rest of the path.
    public static let homePath = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"/(Users|home)/[^/]+/"#,
            options: []
        ),
        replacement: "/$1/[USER]/"
    )

    /// Tilde-prefixed home paths: `~/Library/...` etc.
    /// Replaces `~` with `/Users/[USER]` so the output is consistent.
    public static let tildeHome = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"~/(?=[A-Za-z.])"#,
            options: []
        ),
        replacement: "/Users/[USER]/"
    )

    // MARK: - Tokens and secrets

    /// Bearer token in Authorization headers or standalone.
    public static let bearerToken = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"Bearer\s+[A-Za-z0-9._\-/+]+"#,
            options: []
        ),
        replacement: "Bearer [REDACTED]"
    )

    /// Key-value pairs where the key name implies a secret.
    /// Case-insensitive: `key=abc`, `TOKEN=xyz`, `Api_Key=...`.
    public static let apiKeyValue = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"(key|token|secret|password|api_key|apikey)\s*=\s*\S+"#,
            options: [.caseInsensitive]
        ),
        replacement: "$1=[REDACTED]"
    )

    /// Well-known API key prefixes from common providers.
    public static let apiKeyPrefix = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"(sk-|pk_|rk_|whsec_|SID-)[A-Za-z0-9_\-]+"#,
            options: []
        ),
        replacement: "[REDACTED]"
    )

    /// Full `Authorization:` header lines.
    public static let authHeader = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"Authorization:\s*\S+"#,
            options: [.caseInsensitive]
        ),
        replacement: "Authorization: [REDACTED]"
    )

    /// Environment variables known to contain secrets.
    public static let envVarSecret = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"(ANTHROPIC_API_KEY|OPENAI_API_KEY|GITHUB_TOKEN|FASTMAIL_TOKEN|CLOUDFLARE_TOKEN|HA_TOKEN)\s*=\s*\S+"#,
            options: []
        ),
        replacement: "$1=[REDACTED]"
    )

    // MARK: - Network identifiers

    /// IPv4 addresses (dotted quad).
    public static let ipv4 = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#,
            options: []
        ),
        replacement: "[IP]"
    )

    /// IPv6 addresses (simplified — colon-hex groups, with optional :: compression).
    public static let ipv6 = ScrubberPattern(
        regex: try! NSRegularExpression(
            pattern: #"\b(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:)*::[0-9a-fA-F:]*\b"#,
            options: []
        ),
        replacement: "[IP]"
    )

    // MARK: - Ordered default set

    /// All default patterns in recommended application order.
    ///
    /// Order matters: more specific patterns come first to avoid partial
    /// matches from broader patterns consuming part of a specific one.
    public static let defaults: [ScrubberPattern] = [
        // Secrets first (most specific)
        envVarSecret,
        bearerToken,
        authHeader,
        apiKeyPrefix,
        apiKeyValue,
        // Identity
        email,
        // Network
        ipv4,
        ipv6,
        // Paths last (broadest)
        homePath,
        tildeHome,
    ]
}
