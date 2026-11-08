// "Memory for close-up detail": the texture streaming budget. Automatic follows
// the memory the GPU can use without trouble on this Mac, as Metal reports it,
// minus what is already allocated. docs/rendering/texture-streaming.md has the rule.

import Foundation

nonisolated public enum TextureBudget {
    /// The menu: Automatic, then the fixed choices kept for testing.
    public static var choiceTitles: [String] {
        ["Automatic"] + PlayerSettingsCatalog.textureBudgetOptions.map { "\($0) MiB" }
    }

    public static let smallestBytes = 256 << 20
    public static let largestBytes = 4096 << 20

    /// A quarter of what is left of the working set, so meshes, render targets, and
    /// the next cells keep room. Rounded down to 64 MiB.
    public static func automaticBytes(workingSetBytes: UInt64, allocatedBytes: UInt64) -> Int {
        let free = workingSetBytes > allocatedBytes ? workingSetBytes - allocatedBytes : 0
        let quarter = Int(clamping: free / 4)
        let rounded = quarter / (64 << 20) * (64 << 20)
        return min(max(rounded, smallestBytes), largestBytes)
    }

    /// The bytes for the stored choice; index 0 is Automatic.
    public static func bytes(choice: Int, workingSetBytes: UInt64, allocatedBytes: UInt64) -> Int {
        let options = PlayerSettingsCatalog.textureBudgetOptions
        guard choice > 0 else {
            return automaticBytes(workingSetBytes: workingSetBytes, allocatedBytes: allocatedBytes)
        }
        return options[min(choice - 1, options.count - 1)] << 20
    }
}
