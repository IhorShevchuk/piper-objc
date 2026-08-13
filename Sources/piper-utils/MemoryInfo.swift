import Foundation

public enum MemoryInfo {
    public static func getMemoryUsage() -> UInt64? {
#if canImport(Darwin)
        // macOS implementation using Mach APIs
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return UInt64(info.phys_footprint)
        } else {
            return nil
        }
#else
        // Linux fallback – read from /proc/self/status or return nil
        #if os(Linux)
        if let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) {
            for line in status.split(separator: "\n") {
                if line.hasPrefix("VmRSS:") {
                    // Format: VmRSS:	  12345 kB
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 2, let value = UInt64(parts[1]) {
                        return value * 1024 // kB to bytes
                    }
                }
            }
        }
        return nil
        #else
        return nil
        #endif
#endif
    }
}
