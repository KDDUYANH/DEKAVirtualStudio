//
//  SystemMetrics.swift
//  Real device readings: app memory footprint, battery, free storage.
//

import UIKit
import Darwin

enum SystemMetrics {

    /// Physical memory footprint (what iOS uses to decide jetsam), in MB.
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }

    /// Battery 0…100 and charging flag. Main thread (UIDevice).
    static func battery() -> (percent: Int?, charging: Bool) {
        let d = UIDevice.current
        if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
        let level = d.batteryLevel
        let charging = d.batteryState == .charging || d.batteryState == .full
        return (level < 0 ? nil : Int((level * 100).rounded()), charging)
    }

    /// Free space usable for important data (recordings), in bytes.
    static func freeStorageBytes() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
