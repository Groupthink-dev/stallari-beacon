# Sidereal Beacon

Privacy-first crash reporting, diagnostics, and feedback for [Sidereal](https://sidereal.cc) — the agentic productivity platform for macOS.

Beacon is the open-source telemetry layer that lets Sidereal learn from failures without compromising user trust. Every byte of data collected is defined in this repo, auditable by anyone, and controlled entirely by the user.

## Why This Exists

Sidereal orchestrates AI agents, MCP servers, and background processes on your Mac. When something goes wrong — a subprocess leaks memory, a dispatch job crashes, the app hangs — **the developer needs to know, and you need to stay in control.**

Most crash reporters are black boxes. You can't see what they collect. You can't verify what they send. You just click "Send" and hope.

Beacon is different:

- **Open source.** The entire collection, formatting, and transport layer is here. Read every line.
- **Local-first.** Reports are written to disk before anything is sent. You can inspect, edit, or delete them.
- **Opt-in.** Nothing is ever sent without explicit user consent. Not on first launch. Not silently. Not ever.
- **Structured for humans and machines.** Reports are designed to be useful to a non-developer reading them *and* to automated analysis systems that process them at scale.

## What Beacon Collects

### Crash Reports

When Sidereal or one of its managed processes crashes, Beacon captures:

| Field | Example | Why |
|-------|---------|-----|
| App version | `0.44.3.3` | Which release is affected |
| macOS version | `26.3.0` | OS-specific bugs |
| Crash type | `memory_pressure`, `signal_abort`, `unhandled_exception` | Root cause classification |
| Component | `daemon`, `mcp.sidereal-blade`, `dispatch.daily-digest` | Which subsystem failed |
| Resource snapshot | `rss_mb: 2048, cpu_percent: 98` | Was it a resource issue? |
| Breadcrumbs | `[dispatch_start, mcp_connect, memory_warning, ...]` | What happened leading up to the crash |
| Stack trace (symbolicated) | Top 20 frames | Where in the code it failed |

### What Beacon Does NOT Collect

- Vault contents, note text, or file paths containing note names
- API keys, tokens, or credentials (actively scrubbed)
- Email addresses, calendar events, or personal data
- IP addresses or precise location
- Hostname or machine identifiers (replaced with anonymous device ID)
- MCP tool arguments or responses

### Diagnostics

Periodic health snapshots (when enabled) capture aggregate resource usage:

- Total managed subprocess count and aggregate memory
- Dispatch job success/failure rates (counts only, no content)
- MCP server availability (up/down, not what they're doing)

### User Feedback

Beacon provides the transport layer for in-app feedback:

- User-initiated text feedback (what they typed, nothing more)
- Optional diagnostic bundle attachment (user reviews before sending)
- Satisfaction signals (emoji reactions, feature votes)

## Architecture

```
┌─────────────────────────────────────────────────┐
│  Sidereal App                                   │
│                                                 │
│  ┌───────────┐  ┌───────────┐  ┌────────────┐  │
│  │ Process   │  │  Crash    │  │  Feedback  │  │
│  │ Guardian  │  │  Handler  │  │  UI        │  │
│  └─────┬─────┘  └─────┬─────┘  └─────┬──────┘  │
│        │              │              │          │
│        ▼              ▼              ▼          │
│  ┌─────────────────────────────────────────┐    │
│  │          Beacon SDK (this repo)         │    │
│  │                                         │    │
│  │  Collector → Scrubber → Store → Sender  │    │
│  └─────────────┬───────────────────────────┘    │
│                │                                │
│                ▼                                │
│  ~/.config/sidereal/beacon/                     │
│  ├── pending/          # Reports awaiting send  │
│  ├── sent/             # Sent (pruned at 30d)   │
│  └── config.json       # User preferences       │
└─────────────────────────────────────────────────┘
                 │
                 │  HTTPS (opt-in only)
                 ▼
        ┌─────────────────┐
        │  Beacon Ingest  │  (Cloudflare Worker + R2)
        │  Anonymous POST │
        │  No auth needed │
        └────────┬────────┘
                 │
                 ▼
        ┌─────────────────┐
        │  Analysis       │  (Future: AI-driven triage)
        │  Dashboard      │
        │  Alerting       │
        └─────────────────┘
```

### Key Components

**Collector** — Gathers crash data from Mach exception handlers, POSIX signals, and structured event APIs. Async-signal-safe where required.

**Scrubber** — Strips PII before the report ever hits disk. Applies regex patterns for emails, file paths, API keys, and custom exclusion rules. Aggressively conservative: if in doubt, redact.

**Store** — Writes reports as human-readable JSON to `~/.config/sidereal/beacon/pending/`. Users can open, inspect, edit, or delete any report before it's sent.

**Sender** — Transmits consented reports over HTTPS. Retries with exponential backoff. Reports are immutable after consent — the server receives exactly what the user approved.

## Process Guardian (Companion Component)

While Beacon handles *reporting*, the Process Guardian (in `sidereal-harness`) handles *prevention*. It enforces:

| Guardrail | Mechanism |
|-----------|-----------|
| Memory budget per subprocess | `mach_task_basic_info` polling, configurable RSS ceiling |
| CPU budget per subprocess | `rusage` sampling, sustained-usage threshold |
| Restart circuit breaker | Exponential backoff: 1s → 2s → 4s → ... → max 5min. After N failures in M minutes, stop and alert |
| Subprocess accounting | Track all spawned processes, prevent orphans on app exit |
| Fleet-wide resource ceiling | Total managed process RSS cannot exceed configurable % of system memory |

When a guardrail triggers, the Guardian:
1. Logs the event locally
2. Sends a Beacon diagnostic event (if opted in)
3. Takes corrective action (kill subprocess, pause dispatch, alert user)
4. Notifies via ntfy (if configured)

## User Consent Model

```
First Launch
    │
    ▼
┌─────────────────────────────────────┐
│  "Help improve Sidereal"            │
│                                     │
│  Sidereal can send anonymous crash  │
│  reports when things go wrong.      │
│                                     │
│  • You control what's sent          │
│  • Reports are open source          │
│  • View reports before sending      │
│                                     │
│  [Learn More]  [Not Now]  [Enable]  │
└─────────────────────────────────────┘
    │
    ▼
Settings → Privacy → Beacon
    │
    ├── Crash reports: on/off (default: off)
    ├── Diagnostics: on/off (default: off)
    ├── Review before sending: on/off (default: on)
    ├── View pending reports
    ├── View sent reports
    └── Delete all data
```

**"Not Now" is respected.** No dark patterns. No "remind me later" nag. The setting is always accessible in Privacy preferences.

## Report Format

Reports use a structured JSON format designed for both human readability and machine parsing:

```json
{
  "beacon_version": "1.0.0",
  "report_id": "brpt_a1b2c3d4",
  "type": "crash",
  "timestamp": "2026-04-03T09:15:00+10:00",
  "app": {
    "version": "0.44.3.3",
    "component": "daemon.mcp.sidereal-blade"
  },
  "system": {
    "os_version": "26.3.0",
    "arch": "arm64",
    "memory_gb": 36,
    "memory_pressure": "critical"
  },
  "crash": {
    "type": "memory_pressure",
    "signal": "SIGKILL",
    "jetsam_reason": "per-process-limit",
    "resource_snapshot": {
      "rss_mb": 16384,
      "cpu_percent": 2.1,
      "subprocess_count": 47,
      "total_managed_rss_mb": 28672
    },
    "breadcrumbs": [
      { "t": -300, "event": "dispatch_start", "detail": "daily-digest" },
      { "t": -120, "event": "mcp_spawn", "detail": "subprocess_count=45" },
      { "t": -30,  "event": "memory_warning", "detail": "rss=12288mb" },
      { "t": -5,   "event": "guardian_kill_attempt", "detail": "pid=12345" },
      { "t": 0,    "event": "crash", "detail": "jetsam" }
    ],
    "stack_trace": [
      "0: SiderealDaemon.ProcessManager.spawn(_:) + 0x1a4",
      "1: SiderealDaemon.MCPCoordinator.startServer(_:) + 0x88",
      "..."
    ]
  }
}
```

## Feedback System

Beacon includes a tiered feedback mechanism designed for all user types:

### For Everyone
- **Quick reaction** — Emoji bar (works/broken/confused/love-it) on any screen. Zero friction.
- **"Send Feedback" button** — always accessible from Help menu and Settings. Opens a simple text box.

### For Casual Users
- **Contextual prompts** — after a dispatch failure or unexpected behavior, a non-intrusive banner offers "Something went wrong. Tell us what happened?"
- **Screenshot attachment** — optional, user-initiated, with preview before sending.

### For Technical Users
- **Diagnostic bundle** — one-click export of recent Beacon reports, process state, and (redacted) logs. User reviews contents before sending.
- **Beacon CLI** — `sidereal-cli beacon list`, `beacon inspect <id>`, `beacon send <id>`, `beacon export`. Full control from the terminal.
- **GitHub Issues integration** — "Open as GitHub Issue" pre-fills a template with the diagnostic context (after user review).

## Integration with DevOps

Beacon is one layer in a broader quality practice:

| Layer | Tool | When |
|-------|------|------|
| **Prevent** | SwiftLint, ASan, TSan in CI | Before merge |
| **Detect** | Process Guardian (resource monitoring) | At runtime |
| **Capture** | Beacon SDK (this repo) | On failure |
| **Analyse** | AI triage agent (future) | On report receipt |
| **Respond** | ntfy alerts, GitHub Issues | On severity threshold |
| **Learn** | Trend analysis, regression detection | Continuously |

## Building

```bash
# Clone
git clone https://github.com/groupthink-dev/sidereal-beacon.git
cd sidereal-beacon

# Build the SDK (Swift Package)
swift build

# Run tests
swift test

# Build the ingest worker (Cloudflare Worker)
cd ingest && npm install && npm run build
```

## Project Structure

```
sidereal-beacon/
├── Sources/
│   └── SiderealBeacon/
│       ├── Collector/       # Crash + diagnostic data gathering
│       ├── Scrubber/        # PII removal pipeline
│       ├── Store/           # Local report persistence
│       ├── Sender/          # HTTPS transport
│       ├── Feedback/        # User feedback models
│       └── Guardian/        # Process resource monitoring
├── Tests/
│   └── SiderealBeaconTests/
├── ingest/                  # Cloudflare Worker for report ingestion
├── Package.swift
├── LICENSE                  # MIT
└── README.md
```

## Privacy

Beacon is designed around a simple principle: **the user's machine is theirs, not ours.**

- All collection code is in this public repository
- Reports are stored locally in readable JSON — no binary blobs
- The scrubber runs *before* disk write, not before send
- Users can inspect, edit, or delete any report at any time
- The ingest endpoint accepts anonymous POST — no auth tokens, no user tracking
- We do not correlate reports across devices or sessions
- The anonymous device ID is a random UUID generated once, stored locally, and never linked to any identity

## License

MIT — use it in your own projects. If you build something better, we'd love to know.

## Contributing

This is the kind of project where trust matters more than features. Contributions that improve privacy, auditability, or clarity are especially welcome.

1. Fork the repo
2. Create a branch (`feat/better-scrubber`)
3. Write tests (especially for the scrubber — that's where trust lives)
4. Open a PR

---

*Sidereal Beacon is part of the [Sidereal](https://sidereal.cc) platform by [Groupthink](https://github.com/groupthink-dev).*
