import Foundation
import Testing

@testable import SiderealBeacon

// MARK: - Scrubber Tests

@Suite("PIIScrubber")
struct ScrubberTests {

    let scrubber = PIIScrubber()

    // MARK: - Email

    @Test("Scrubs email addresses")
    func emailScrubbing() {
        let input = "Contact user@example.com for details"
        let result = scrubber.scrub(input)
        #expect(result == "Contact [EMAIL] for details")
    }

    @Test("Scrubs multiple email addresses in one string")
    func multipleEmails() {
        let input = "From alice@foo.org to bob@bar.co.uk"
        let result = scrubber.scrub(input)
        #expect(result == "From [EMAIL] to [EMAIL]")
    }

    @Test("Scrubs email with plus addressing")
    func emailPlusAddressing() {
        let input = "user+tag@example.com"
        let result = scrubber.scrub(input)
        #expect(result == "[EMAIL]")
    }

    // MARK: - Home paths

    @Test("Scrubs /Users/<username>/ paths")
    func homePathScrubbing() {
        let input = "/Users/piers/Documents/secret.md"
        let result = scrubber.scrub(input)
        #expect(result == "/Users/[USER]/Documents/secret.md")
    }

    @Test("Scrubs /home/<username>/ paths")
    func linuxHomePathScrubbing() {
        let input = "/home/deploy/.config/sidereal/beacon"
        let result = scrubber.scrub(input)
        #expect(result == "/home/[USER]/.config/sidereal/beacon")
    }

    @Test("Scrubs tilde paths to consistent format")
    func tildePathScrubbing() {
        let input = "~/Documents/file.txt"
        let result = scrubber.scrub(input)
        #expect(result == "/Users/[USER]/Documents/file.txt")
    }

    @Test("Does not scrub bare tilde without path continuation")
    func bareTildePreserved() {
        let input = "The ~ character is fine"
        let result = scrubber.scrub(input)
        #expect(result == "The ~ character is fine")
    }

    // MARK: - Bearer tokens

    @Test("Scrubs bearer tokens")
    func bearerTokenScrubbing() {
        let input = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc123.xyz"
        let result = scrubber.scrub(input)
        #expect(result == "Bearer [REDACTED]")
    }

    // MARK: - API key prefixes

    @Test("Scrubs sk- prefix keys")
    func skPrefixScrubbing() {
        let input = "Using key sk-ant-api03-abcdef1234567890"
        let result = scrubber.scrub(input)
        #expect(result == "Using key [REDACTED]")
    }

    @Test("Scrubs pk_ prefix keys")
    func pkPrefixScrubbing() {
        let input = "Stripe key pk_test_abc123def456"
        let result = scrubber.scrub(input)
        #expect(result == "Stripe key [REDACTED]")
    }

    @Test("Scrubs SID- prefix keys")
    func sidPrefixScrubbing() {
        let input = "License SID-abc123def456"
        let result = scrubber.scrub(input)
        #expect(result == "License [REDACTED]")
    }

    @Test("Scrubs rk_ prefix keys")
    func rkPrefixScrubbing() {
        let input = "Resend key rk_live_abc123"
        let result = scrubber.scrub(input)
        #expect(result == "Resend key [REDACTED]")
    }

    @Test("Scrubs whsec_ prefix keys")
    func whsecPrefixScrubbing() {
        let input = "Webhook secret whsec_abc123def456"
        let result = scrubber.scrub(input)
        #expect(result == "Webhook secret [REDACTED]")
    }

    // MARK: - Key=value pairs

    @Test("Scrubs token=value pairs")
    func tokenValueScrubbing() {
        let input = "token=abc123secret"
        let result = scrubber.scrub(input)
        #expect(result == "token=[REDACTED]")
    }

    @Test("Scrubs key=value pairs case-insensitively")
    func keyValueCaseInsensitive() {
        let input = "API_KEY=mysecretkey123"
        let result = scrubber.scrub(input)
        #expect(result == "API_KEY=[REDACTED]")
    }

    @Test("Scrubs password=value pairs")
    func passwordValueScrubbing() {
        let input = "password=hunter2"
        let result = scrubber.scrub(input)
        #expect(result == "password=[REDACTED]")
    }

    // MARK: - Environment variables

    @Test("Scrubs ANTHROPIC_API_KEY env var")
    func anthropicApiKeyScrubbing() {
        let input = "ANTHROPIC_API_KEY=sk-ant-api03-xxxxxxxxxxxx"
        let result = scrubber.scrub(input)
        // envVarSecret runs first, then apiKeyPrefix may clean up the value
        #expect(!result.contains("sk-ant-api03"))
        #expect(result.contains("ANTHROPIC_API_KEY"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("Scrubs OPENAI_API_KEY env var")
    func openaiApiKeyScrubbing() {
        let input = "OPENAI_API_KEY=sk-proj-abc123"
        let result = scrubber.scrub(input)
        #expect(!result.contains("sk-proj-abc123"))
        #expect(result.contains("OPENAI_API_KEY"))
        #expect(result.contains("[REDACTED]"))
    }

    @Test("Scrubs GITHUB_TOKEN env var")
    func githubTokenScrubbing() {
        let input = "GITHUB_TOKEN=ghp_abcdef1234567890"
        let result = scrubber.scrub(input)
        #expect(!result.contains("ghp_abcdef1234567890"))
        #expect(result.contains("GITHUB_TOKEN"))
        #expect(result.contains("[REDACTED]"))
    }

    // MARK: - IPv4

    @Test("Scrubs IPv4 addresses")
    func ipv4Scrubbing() {
        let input = "Connected to 192.168.1.100 on port 9847"
        let result = scrubber.scrub(input)
        #expect(result == "Connected to [IP] on port 9847")
    }

    @Test("Scrubs multiple IPv4 addresses")
    func multipleIpv4() {
        let input = "Route: 10.0.0.1 -> 172.16.0.5"
        let result = scrubber.scrub(input)
        #expect(result == "Route: [IP] -> [IP]")
    }

    // MARK: - Auth headers

    @Test("Scrubs Authorization header lines")
    func authHeaderScrubbing() {
        // authHeader pattern matches Authorization:\s*\S+ (one token after colon)
        let input = "Authorization: SecretToken123"
        let result = scrubber.scrub(input)
        #expect(result == "Authorization: [REDACTED]")
    }

    @Test("Scrubs Authorization header case-insensitively")
    func authHeaderCaseInsensitive() {
        let input = "authorization: mytoken123"
        let result = scrubber.scrub(input)
        #expect(result == "Authorization: [REDACTED]")
    }

    @Test("Scrubs multi-part Authorization header (Bearer handled by bearerToken pattern)")
    func authHeaderBearer() {
        let input = "Authorization: Bearer abc123.def456.ghi789"
        let result = scrubber.scrub(input)
        // bearerToken fires first: "Bearer abc123..." -> "Bearer [REDACTED]"
        // authHeader then matches "Authorization: Bearer" -> "Authorization: [REDACTED]"
        // Final result has [REDACTED] remaining from bearer replacement
        #expect(result.contains("Authorization:"))
        #expect(result.contains("[REDACTED]"))
        #expect(!result.contains("abc123"))
    }

    // MARK: - Stack trace scrubbing

    @Test("Scrubs file paths in stack traces while preserving function names")
    func stackTraceScrubbing() {
        let frames = [
            "0  SiderealHarness  0x0001234  DaemonLifecycleManager.start() + 42",
            "1  SiderealHarness  0x0005678  /Users/piers/src/sidereal-harness/Sources/Daemon.swift:120",
            "2  libswiftCore.dylib  0x0009abc  Swift.Array.map() + 99",
        ]
        let crash = CrashReport(
            type: .signalAbort,
            signal: "SIGABRT",
            resourceSnapshot: ResourceSnapshot(rssMb: 100, cpuPercent: 45.0, subprocessCount: 3, totalManagedRssMb: 300),
            stackTrace: frames
        )
        let report = makeTestReport(payload: .crash(crash))
        let scrubbed = scrubber.scrub(report)

        guard case .crash(let scrubbedCrash) = scrubbed.payload else {
            Issue.record("Expected crash payload")
            return
        }

        // Function names preserved
        #expect(scrubbedCrash.stackTrace[0].contains("DaemonLifecycleManager.start()"))
        // Path scrubbed
        #expect(scrubbedCrash.stackTrace[1].contains("/Users/[USER]/"))
        #expect(!scrubbedCrash.stackTrace[1].contains("/Users/piers/"))
        // System frames untouched
        #expect(scrubbedCrash.stackTrace[2].contains("Swift.Array.map()"))
    }

    // MARK: - Breadcrumb detail scrubbing

    @Test("Scrubs PII from breadcrumb details but preserves event names")
    func breadcrumbDetailScrubbing() {
        let breadcrumbs = [
            Breadcrumb(t: -5.0, event: "mcp.start", detail: "Started at /Users/piers/.config/sidereal"),
            Breadcrumb(t: -3.0, event: "dispatch.begin", detail: "token=secret123"),
            Breadcrumb(t: -1.0, event: "error", detail: nil),
        ]
        let crash = CrashReport(
            type: .unhandledException,
            resourceSnapshot: ResourceSnapshot(rssMb: 50, cpuPercent: 10.0, subprocessCount: 1, totalManagedRssMb: 50),
            breadcrumbs: breadcrumbs
        )
        let report = makeTestReport(payload: .crash(crash))
        let scrubbed = scrubber.scrub(report)

        guard case .crash(let scrubbedCrash) = scrubbed.payload else {
            Issue.record("Expected crash payload")
            return
        }

        // Event names preserved
        #expect(scrubbedCrash.breadcrumbs[0].event == "mcp.start")
        #expect(scrubbedCrash.breadcrumbs[1].event == "dispatch.begin")
        #expect(scrubbedCrash.breadcrumbs[2].event == "error")

        // Path scrubbed in detail
        #expect(scrubbedCrash.breadcrumbs[0].detail?.contains("[USER]") == true)
        #expect(scrubbedCrash.breadcrumbs[0].detail?.contains("piers") != true)

        // Token scrubbed in detail
        #expect(scrubbedCrash.breadcrumbs[1].detail?.contains("secret123") != true)
        #expect(scrubbedCrash.breadcrumbs[1].detail?.contains("[REDACTED]") == true)

        // Nil detail stays nil
        #expect(scrubbedCrash.breadcrumbs[2].detail == nil)
    }

    // MARK: - Full report round-trip

    @Test("Full report round-trip: create with PII, scrub, verify PII removed")
    func fullReportRoundTrip() {
        let crash = CrashReport(
            type: .memoryPressure,
            jetsamReason: "per-process-limit",
            resourceSnapshot: ResourceSnapshot(rssMb: 2048, cpuPercent: 95.0, subprocessCount: 12, totalManagedRssMb: 4096),
            breadcrumbs: [
                Breadcrumb(t: -10.0, event: "mcp.connect", detail: "user@example.com connected from 192.168.1.50"),
                Breadcrumb(t: -5.0, event: "config.load", detail: "path=/Users/piers/master-ai/.config"),
            ],
            stackTrace: [
                "0  SiderealHarness  DaemonLifecycleManager.handleMemoryWarning()",
                "1  SiderealHarness  /Users/piers/src/sidereal-harness/Sources/Guardian/ProcessGuardian.swift:225",
                "2  libsystem_malloc  malloc_zone_error",
            ]
        )

        let report = makeTestReport(payload: .crash(crash))
        let scrubbed = scrubber.scrub(report)

        // Encode to JSON string for comprehensive check
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(scrubbed)
        let json = String(data: data, encoding: .utf8)!

        // PII must not appear
        #expect(!json.contains("user@example.com"))
        #expect(!json.contains("192.168.1.50"))
        #expect(!json.contains("/Users/piers/"))

        // Structural data must be preserved
        #expect(json.contains("memory_pressure"))
        #expect(json.contains("per-process-limit"))
        #expect(json.contains("DaemonLifecycleManager.handleMemoryWarning()"))
        #expect(json.contains("[EMAIL]"))
        #expect(json.contains("[IP]"))
        #expect(json.contains("[USER]"))

        // Report identity preserved
        #expect(scrubbed.reportId == report.reportId)
        #expect(scrubbed.type == .crash)
    }

    // MARK: - Feedback scrubbing

    @Test("Scrubs feedback message and context screen")
    func feedbackScrubbing() {
        let feedback = FeedbackReport(
            message: "Crash at /Users/piers/Documents/vault when using token=abc123",
            reaction: .broken,
            contextScreen: "/Users/piers/src/sidereal-harness/Views/Settings",
            includesDiagnosticBundle: false
        )
        let report = makeTestReport(payload: .feedback(feedback))
        let scrubbed = scrubber.scrub(report)

        guard case .feedback(let scrubbedFeedback) = scrubbed.payload else {
            Issue.record("Expected feedback payload")
            return
        }

        #expect(!scrubbedFeedback.message.contains("piers"))
        #expect(scrubbedFeedback.message.contains("[USER]"))
        #expect(scrubbedFeedback.message.contains("[REDACTED]"))
        #expect(!scrubbedFeedback.contextScreen!.contains("piers"))
        #expect(scrubbedFeedback.reaction == .broken)
        #expect(scrubbedFeedback.includesDiagnosticBundle == false)
    }

    // MARK: - Diagnostic reports pass through

    @Test("Diagnostic reports are not modified by scrubber")
    func diagnosticPassthrough() {
        let diagnostic = DiagnosticReport(
            subprocessCount: 5,
            totalManagedRssMb: 1024,
            systemMemoryPressure: .warn,
            dispatchStats: DispatchStats(jobsStarted: 10, jobsSucceeded: 8, jobsFailed: 2, since: Date()),
            mcpAvailability: [MCPStatus(name: "sidereal-blade", isAvailable: true)]
        )
        let report = makeTestReport(payload: .diagnostic(diagnostic))
        let scrubbed = scrubber.scrub(report)

        #expect(scrubbed.payload == report.payload)
    }

    // MARK: - Multiple patterns in one string

    @Test("Applies multiple patterns to a single string")
    func multiplePatternsInOneString() {
        let input = "User user@example.com at /Users/piers/Documents with token=secret123 from 10.0.0.1"
        let result = scrubber.scrub(input)

        #expect(!result.contains("user@example.com"))
        #expect(!result.contains("/Users/piers/"))
        #expect(!result.contains("secret123"))
        #expect(!result.contains("10.0.0.1"))
        #expect(result.contains("[EMAIL]"))
        #expect(result.contains("[USER]"))
        #expect(result.contains("[REDACTED]"))
        #expect(result.contains("[IP]"))
    }

    // MARK: - Custom patterns

    @Test("Custom patterns are applied after defaults")
    func customPatterns() {
        let customScrubber = PIIScrubber(customPatterns: [
            (pattern: #"vault_id=[A-Za-z0-9]+"#, replacement: "vault_id=[REDACTED]"),
        ])
        let input = "Loading vault_id=abc123def456"
        let result = customScrubber.scrub(input)
        #expect(result == "Loading vault_id=[REDACTED]")
    }

    @Test("Invalid custom pattern is silently ignored")
    func invalidCustomPattern() {
        let customScrubber = PIIScrubber(customPatterns: [
            (pattern: "[invalid(", replacement: "nope"),
        ])
        // Should not crash; default patterns still work
        let result = customScrubber.scrub("user@example.com")
        #expect(result == "[EMAIL]")
    }

    // MARK: - Helpers

    private func makeTestReport(payload: ReportPayload) -> BeaconReport {
        let type: ReportType
        switch payload {
        case .crash: type = .crash
        case .diagnostic: type = .diagnostic
        case .feedback: type = .feedback
        }
        return BeaconReport(
            reportId: "brpt_testtest",
            type: type,
            timestamp: Date(),
            app: AppInfo(version: "0.44.0.0", component: "daemon"),
            system: SystemInfo(osVersion: "15.3.1", arch: "arm64", memoryGb: 36, memoryPressure: .nominal),
            payload: payload
        )
    }
}
