import Foundation
import Darwin

// MARK: - MemoryPressure

/// System memory pressure level.
public enum MemoryPressure: String, Codable, Sendable {
    case nominal
    case warn
    case critical
}

// MARK: - SystemInfo

/// System metadata auto-populated from the running environment.
public struct SystemInfo: Codable, Sendable, Equatable {
    /// macOS version string (e.g. "15.3.1").
    public let osVersion: String

    /// CPU architecture (e.g. "arm64", "x86_64").
    public let arch: String

    /// Physical memory in whole gigabytes.
    public let memoryGb: Int

    /// Current memory pressure level.
    public let memoryPressure: MemoryPressure

    public init(osVersion: String, arch: String, memoryGb: Int, memoryPressure: MemoryPressure) {
        self.osVersion = osVersion
        self.arch = arch
        self.memoryGb = memoryGb
        self.memoryPressure = memoryPressure
    }

    /// Build a `SystemInfo` from the current system state.
    public static func current() -> SystemInfo {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        let arch = currentArch()
        let memoryGb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let pressure = currentMemoryPressure()

        return SystemInfo(
            osVersion: versionString,
            arch: arch,
            memoryGb: memoryGb,
            memoryPressure: pressure
        )
    }

    private enum CodingKeys: String, CodingKey {
        case osVersion = "os_version"
        case arch
        case memoryGb = "memory_gb"
        case memoryPressure = "memory_pressure"
    }

    // MARK: - Private helpers

    private static func currentArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    private static func currentMemoryPressure() -> MemoryPressure {
        // DispatchSource.MemoryPressureEvent only fires on active sources.
        // For a point-in-time snapshot we use host_statistics64 instead.
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return .nominal
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let compressedRatio = Double(compressedBytes) / Double(totalMemory)

        // Heuristic thresholds aligned with macOS memory pressure levels.
        if compressedRatio > 0.50 {
            return .critical
        } else if compressedRatio > 0.25 {
            return .warn
        } else {
            return .nominal
        }
    }
}
