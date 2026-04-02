// MARK: - SiderealBeacon Public API Exports
//
// Barrel file for convenient single-import access to all public types.
// Consumers write `import SiderealBeacon` and get everything they need.

// Foundation is already imported transitively by every source file in the
// module. An `@_exported import Foundation` here would re-export Foundation's
// entire namespace through SiderealBeacon, which is intentionally avoided —
// consumers should import Foundation themselves if they need it directly.

// All public types are accessible via `import SiderealBeacon`:
//
// Orchestrator:
//   - Beacon                    (public actor — top-level entry point)
//
// Models:
//   - BeaconReport              (report envelope)
//   - ReportType                (crash | diagnostic | feedback)
//   - ReportPayload             (associated payload enum)
//   - AppInfo                   (app metadata)
//   - SystemInfo                (system metadata)
//   - MemoryPressure            (nominal | warn | critical)
//   - CrashReport               (crash payload)
//   - CrashType                 (crash classification)
//   - DiagnosticReport          (diagnostic payload)
//   - DispatchStats             (dispatch job statistics)
//   - MCPStatus                 (MCP server availability)
//   - FeedbackReport            (feedback payload)
//   - ReactionType              (feedback sentiment)
//   - Breadcrumb                (crash timeline event)
//   - ResourceSnapshot          (point-in-time resource state)
//   - BeaconConfig              (user preferences)
//
// Subsystems:
//   - ReportStore               (on-disk report persistence)
//   - ReportStoreError          (store error types)
//   - ReportSender              (HTTPS report transmission)
//   - SendResult                (batch send summary)
//   - SendError                 (transmission errors)
//   - ConsentGate               (consent check)
//   - PIIScrubber               (PII redaction)
//   - CrashCollector            (signal-based crash capture)
//   - DiagnosticCollector        (periodic health snapshots)
//   - BreadcrumbTrail           (ring buffer of recent events)
//   - ProcessGuardian           (subprocess resource monitoring)
//   - ProcessGuardianProvider   (guardian protocol for DI)
//   - ManagedProcess            (registered subprocess)
//   - ProcessHealth             (subprocess health snapshot)
//   - GuardianAction            (enforcement recommendation)
//   - GuardianDelegate          (guardian event delegate)
//   - CircuitBreaker            (restart loop prevention)
//   - CircuitStatus             (circuit breaker state)
//   - FeedbackCollector         (user feedback packaging)
