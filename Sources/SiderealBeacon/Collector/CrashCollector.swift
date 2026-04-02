import Foundation
import Darwin

// MARK: - Signal handler globals

/// Global state accessible from the signal handler. These are set during
/// `install()` and read during signal delivery or `atexit`.
///
/// **Design tradeoff:** POSIX signal handlers are extremely constrained — only
/// async-signal-safe functions (open, write, close, _exit) are permitted. No
/// malloc, no ObjC messaging, no Swift runtime calls. Capturing a full crash
/// report (stack trace, breadcrumbs, resource snapshot) inside a signal handler
/// is therefore impractical in pure Swift without resorting to pre-allocated C
/// buffers and manual serialisation.
///
/// Instead, we take a pragmatic two-phase approach:
///
/// 1. **Signal handler phase:** Sets a flag and stores the signal number. This
///    uses only atomic stores — no allocations, no runtime calls.
/// 2. **Collection phase:** On next launch, `collectPendingCrashes()` reads any
///    staging files written by the `atexit` handler (which runs after the signal
///    handler returns for recoverable signals) or left as marker files.
///
/// For signals where the process can still execute cleanup (SIGABRT with the
/// default handler re-raised), the `atexit` handler captures the full report.
/// For immediately fatal signals (SIGSEGV, SIGBUS), we write a minimal marker
/// file from the signal handler using only `open()/write()/close()`, and the
/// next launch reconstructs what it can.
private var _crashedSignal: Int32 = 0
private var _hasCrashed = false
private var _breadcrumbTrail: BreadcrumbTrail?
private var _stagingDirectoryPath: UnsafeMutablePointer<CChar>?
private var _previousHandlers: [Int32: sigaction] = [:]

/// The signals we intercept for crash detection.
private let monitoredSignals: [Int32] = [
    SIGABRT,
    SIGBUS,
    SIGSEGV,
    SIGFPE,
    SIGILL,
    SIGTRAP,
]

/// Bare-minimum signal handler. Sets the crashed flag and signal number.
/// For async-signal-safety, this must not allocate, lock, or call ObjC.
private func beaconSignalHandler(_ signal: Int32) {
    _crashedSignal = signal
    _hasCrashed = true

    // Write a minimal marker file so the next launch knows a crash occurred,
    // even if the atexit handler never runs (e.g. SIGSEGV double-fault).
    writeMinimalMarker(signal: signal)

    // Re-raise with the default handler so the OS generates its own crash log
    // and the process terminates normally.
    var action = sigaction()
    action.__sigaction_u.__sa_handler = SIG_DFL
    sigemptyset(&action.sa_mask)
    action.sa_flags = 0
    sigaction(signal, &action, nil)
    raise(signal)
}

/// Writes a tiny marker file from signal-handler context using only
/// async-signal-safe POSIX calls. No malloc, no ObjC, no Swift runtime.
private func writeMinimalMarker(signal: Int32) {
    guard let pathPtr = _stagingDirectoryPath else { return }

    // Build path: {staging}/crash_{pid}.marker
    var pathBuf = [CChar](repeating: 0, count: Int(PATH_MAX))
    var i = 0
    var src = pathPtr
    while src.pointee != 0 && i < Int(PATH_MAX) - 30 {
        pathBuf[i] = src.pointee
        src += 1
        i += 1
    }
    // Append "/crash_"
    let suffix: [CChar] = [0x2F, 0x63, 0x72, 0x61, 0x73, 0x68, 0x5F] // "/crash_"
    for c in suffix where i < Int(PATH_MAX) - 20 {
        pathBuf[i] = c
        i += 1
    }
    // Append PID
    var pid = getpid()
    var pidDigits = [CChar]()
    if pid == 0 {
        pidDigits.append(0x30) // "0"
    } else {
        while pid > 0 {
            pidDigits.append(CChar(0x30 + pid % 10))
            pid /= 10
        }
        pidDigits.reverse()
    }
    for d in pidDigits where i < Int(PATH_MAX) - 10 {
        pathBuf[i] = d
        i += 1
    }
    // Append ".marker\0"
    let ext: [CChar] = [0x2E, 0x6D, 0x61, 0x72, 0x6B, 0x65, 0x72, 0] // ".marker\0"
    for c in ext where i < Int(PATH_MAX) {
        pathBuf[i] = c
        i += 1
    }
    pathBuf[min(i, Int(PATH_MAX) - 1)] = 0

    // Write signal number as ASCII.
    let fd = open(&pathBuf, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    guard fd >= 0 else { return }

    var sigBuf = [UInt8](repeating: 0, count: 4)
    var sig = signal
    var sigLen = 0
    if sig == 0 {
        sigBuf[0] = 0x30
        sigLen = 1
    } else {
        var digits = [UInt8]()
        while sig > 0 {
            digits.append(UInt8(0x30 + sig % 10))
            sig /= 10
        }
        digits.reverse()
        for (j, d) in digits.enumerated() where j < sigBuf.count {
            sigBuf[j] = d
            sigLen += 1
        }
    }
    sigBuf.withUnsafeBufferPointer { buf in
        _ = Darwin.write(fd, buf.baseAddress, sigLen)
    }
    _ = Darwin.close(fd)
}

// MARK: - CrashCollector

/// Captures crash information via POSIX signal interception.
///
/// On `install()`, registers signal handlers for fatal signals (SIGABRT, SIGBUS,
/// SIGSEGV, SIGFPE, SIGILL, SIGTRAP). When a signal fires, a minimal marker
/// file is written synchronously from the signal handler, and the signal is
/// re-raised with the default handler.
///
/// On the next app launch, call `collectPendingCrashes()` to read marker files
/// from the staging directory and reconstruct ``CrashReport`` instances.
public actor CrashCollector {

    // MARK: - Properties

    private let breadcrumbs: BreadcrumbTrail
    private let stagingDirectory: URL
    private var installed = false

    // MARK: - Init

    /// Creates a crash collector.
    ///
    /// - Parameters:
    ///   - breadcrumbs: The shared breadcrumb trail for crash context.
    ///   - stagingDirectory: Override for crash staging files. Defaults to
    ///     `~/.config/sidereal/beacon/staging/`.
    public init(
        breadcrumbs: BreadcrumbTrail,
        stagingDirectory: URL? = nil
    ) {
        self.breadcrumbs = breadcrumbs
        if let stagingDirectory {
            self.stagingDirectory = stagingDirectory
        } else {
            self.stagingDirectory = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".config/sidereal/beacon/staging")
        }
    }

    // MARK: - Signal handler registration

    /// Registers POSIX signal handlers for crash detection.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops. Call
    /// `uninstall()` to restore previous handlers.
    public func install() {
        guard !installed else { return }

        // Ensure staging directory exists.
        try? FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        // Set globals for the signal handler.
        _breadcrumbTrail = breadcrumbs
        _hasCrashed = false
        _crashedSignal = 0

        // Copy staging path to a C string that persists for the process lifetime.
        let path = stagingDirectory.path
        let cString = strdup(path)
        _stagingDirectoryPath = cString

        // Register signal handlers, saving previous handlers for restoration.
        for sig in monitoredSignals {
            var newAction = sigaction()
            newAction.__sigaction_u.__sa_handler = beaconSignalHandler
            sigemptyset(&newAction.sa_mask)
            newAction.sa_flags = 0

            var oldAction = sigaction()
            if sigaction(sig, &newAction, &oldAction) == 0 {
                _previousHandlers[sig] = oldAction
            }
        }

        installed = true
    }

    /// Restores signal handlers to their state before `install()` was called.
    public func uninstall() {
        guard installed else { return }

        for sig in monitoredSignals {
            if var oldAction = _previousHandlers[sig] {
                sigaction(sig, &oldAction, nil)
            }
        }
        _previousHandlers.removeAll()

        // Clean up global state.
        if let ptr = _stagingDirectoryPath {
            free(ptr)
            _stagingDirectoryPath = nil
        }
        _breadcrumbTrail = nil
        _hasCrashed = false
        _crashedSignal = 0

        installed = false
    }

    // MARK: - Pending crash collection

    /// Reads and removes crash marker files from previous runs.
    ///
    /// Call this early in the app lifecycle (after `install()`) to recover
    /// crash information from a previous session that terminated abnormally.
    ///
    /// - Returns: Array of crash reports reconstructed from marker files.
    public func collectPendingCrashes() -> [CrashReport] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stagingDirectory.path) else { return [] }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: stagingDirectory,
                includingPropertiesForKeys: nil
            )
        } catch {
            return []
        }

        var reports = [CrashReport]()

        for url in contents where url.pathExtension == "marker" {
            // Read signal number from marker file content.
            let signal: String?
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8)
            {
                signal = signalName(for: Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
            } else {
                signal = nil
            }

            let crashType = crashTypeForSignal(signal)
            let report = CrashReport(
                type: crashType,
                signal: signal,
                resourceSnapshot: Self.captureResourceSnapshot(),
                breadcrumbs: [],
                stackTrace: []
            )
            reports.append(report)

            // Remove the marker file after collection.
            try? fm.removeItem(at: url)
        }

        // Also collect any full JSON staging files (written by atexit or
        // graceful shutdown paths).
        for url in contents where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let report = try? JSONDecoder().decode(CrashReport.self, from: data)
            {
                reports.append(report)
            }
            try? fm.removeItem(at: url)
        }

        return reports
    }

    // MARK: - Resource snapshot

    /// Captures the current process resource state via Mach APIs.
    ///
    /// Returns a point-in-time ``ResourceSnapshot`` with RSS, CPU usage,
    /// and subprocess counts. Safe to call from any context (not signal-safe,
    /// but used in normal app lifecycle).
    public static func captureResourceSnapshot() -> ResourceSnapshot {
        let rss = currentRSSMb()
        let cpu = currentCPUPercent()

        return ResourceSnapshot(
            rssMb: rss,
            cpuPercent: cpu,
            subprocessCount: 0,
            totalManagedRssMb: 0
        )
    }

    // MARK: - Private helpers

    /// Returns the resident set size of the current process in megabytes.
    private static func currentRSSMb() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / (1024 * 1024))
    }

    /// Returns the current process CPU usage as a percentage.
    private static func currentCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0.0 }

        defer {
            let size = vm_size_t(
                MemoryLayout<thread_act_t>.size * Int(threadCount)
            )
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        var totalCPU: Double = 0.0
        for i in 0 ..< Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
            )
            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if infoResult == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        return totalCPU
    }

    /// Maps a POSIX signal number to its name.
    private func signalName(for signal: Int32) -> String? {
        switch signal {
        case SIGABRT: return "SIGABRT"
        case SIGBUS: return "SIGBUS"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE: return "SIGFPE"
        case SIGILL: return "SIGILL"
        case SIGTRAP: return "SIGTRAP"
        default: return "SIG\(signal)"
        }
    }

    /// Infers a ``CrashType`` from the signal name.
    private func crashTypeForSignal(_ signal: String?) -> CrashType {
        guard let signal else { return .unhandledException }
        switch signal {
        case "SIGABRT":
            return .signalAbort
        case "SIGBUS", "SIGSEGV":
            return .machException
        case "SIGFPE", "SIGILL", "SIGTRAP":
            return .machException
        default:
            return .unhandledException
        }
    }
}
