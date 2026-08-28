import AppKit
import Foundation
import IOKit.ps

/// Native replacement for the fastfetch modules sereno used
/// (os/kernel/shell/terminal/theme/display/uptime/cpu/memory/disk in
/// sereno/fastfetch.jsonc). vidrio already knows its own shell and identity,
/// so those two are cheaper here than they were for fastfetch.
enum SystemInfo {
    struct Line {
        let key: String
        let value: String
    }

    static func lines(shellExecutable: String) -> [Line] {
        [
            Line(key: "os", value: osName()),
            Line(key: "ker", value: kernelRelease()),
            Line(key: "sh", value: (shellExecutable as NSString).lastPathComponent),
            Line(key: "term", value: "vidrio"),
            Line(key: "theme", value: interfaceTheme()),
            Line(key: "disp", value: displayInfo()),
            Line(key: "up", value: uptime()),
            Line(key: "cpu", value: cpuBrand()),
            Line(key: "ram", value: memoryUsage()),
            Line(key: "disk", value: diskUsage()),
        ]
    }

    private static func osName() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var name = "macOS"
        if let plist = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist"),
           let productName = plist["ProductName"] as? String {
            name = productName
        }
        return "\(name) \(v.majorVersion).\(v.minorVersion)\(v.patchVersion > 0 ? ".\(v.patchVersion)" : "")"
    }

    private static func kernelRelease() -> String {
        sysctlString("kern.osrelease") ?? "unknown"
    }

    private static func interfaceTheme() -> String {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? "Dark" : "Light"
    }

    private static func displayInfo() -> String {
        let displayID = CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return "unknown" }
        let refresh = mode.refreshRate
        // Built-in panels commonly report 0Hz through this API — omit rather
        // than print a bogus "@ 0Hz".
        if refresh > 0 {
            return "\(mode.pixelWidth)x\(mode.pixelHeight) @ \(Int(refresh))Hz"
        }
        return "\(mode.pixelWidth)x\(mode.pixelHeight)"
    }

    private static func uptime() -> String {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0 else { return "unknown" }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boottime.tv_sec))
        let elapsed = Int(Date().timeIntervalSince(bootDate))
        let days = elapsed / 86400
        let hours = (elapsed % 86400) / 3600
        let minutes = (elapsed % 3600) / 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        parts.append("\(minutes)m")
        return parts.joined(separator: " ")
    }

    private static func cpuBrand() -> String {
        sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "unknown"
    }

    private static func memoryUsage() -> String {
        let total = sysctlUInt64("hw.memsize") ?? 0

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return "\(formatBytes(total)) total"
        }
        let pageSize = sysctlUInt64("hw.pagesize") ?? 4096
        let usedPages = UInt64(vmStats.active_count) + UInt64(vmStats.wire_count) + UInt64(vmStats.compressor_page_count)
        return "\(formatBytes(usedPages * pageSize)) / \(formatBytes(total))"
    }

    private static func diskUsage() -> String {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize] as? UInt64,
              let free = attrs[.systemFreeSize] as? UInt64
        else { return "unknown" }
        return "\(formatBytes(total - free)) / \(formatBytes(total))"
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        if let terminator = buffer.firstIndex(of: 0) { buffer.removeSubrange(terminator...) }
        return String(decoding: buffer, as: UTF8.self)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// Replaces sereno's `pmset -g batt` shell-out for auto display mode.
    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String
            else { continue }
            return state == kIOPSBatteryPowerValue
        }
        return false
    }
}
