// Process memory reading for streaming safeguards (M3.2 memory budget). Reads
// task_vm_info.phys_footprint via task_info(TASK_VM_INFO) -- Apple's
// ledger-based physical-footprint accounting, the same number Activity
// Monitor's Memory column and jetsam use. Ref: Darwin <mach/task_info.h>
// (TASK_VM_INFO / task_vm_info_data_t.phys_footprint). Used to log footprint
// per integrated cell and to fail the streaming test before a runaway can lock
// the machine. See docs/engine/cell-streaming.md (memory budget).

import Darwin
import Foundation

nonisolated enum MemoryFootprint {
    /// Physical footprint in bytes, or nil if the mach call fails.
    static func physFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// Physical footprint in megabytes (1 MB = 1024*1024 B), or nil on failure.
    static func physFootprintMB() -> Double? {
        physFootprintBytes().map { Double($0) / (1024 * 1024) }
    }
}
