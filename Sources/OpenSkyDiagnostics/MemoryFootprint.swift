// Process memory for the streaming memory budget. Reads
// `task_vm_info.phys_footprint` through `task_info(TASK_VM_INFO)`, the same
// number Activity Monitor's Memory column and jetsam use (<mach/task_info.h>).
// It fails the streaming test before a runaway can lock the machine.
// See docs/engine/cell-streaming.md (memory budget).

import Darwin
import Foundation

nonisolated public enum MemoryFootprint: Sendable {
    /// Physical footprint in bytes, or nil if the mach call fails.
    public static func physFootprintBytes() -> UInt64? {
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
    public static func physFootprintMB() -> Double? {
        physFootprintBytes().map { Double($0) / (1024 * 1024) }
    }
}
