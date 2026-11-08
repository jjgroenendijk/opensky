// Switches for the load-time optimisations, so one build can measure each one on and
// off. The app sets them from the `loading.*` player settings at each world load;
// `openskycli load-pass --set` sets them for a run (docs/tools/benchmark.md).

import Synchronization

nonisolated public struct LoadOptimisations: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Opening a plugin starts reading the whole file into the page cache.
    public static let pluginReadAhead = Self(rawValue: 1 << 0)
    /// An archive read asks for its whole byte range at once.
    public static let archiveReadAhead = Self(rawValue: 1 << 1)
    /// A record type's records decode on every core.
    public static let parallelRecords = Self(rawValue: 1 << 2)
    /// The FormID index of each plugin, and each large group in it, builds on its own core.
    public static let parallelFormIDIndex = Self(rawValue: 1 << 3)
    /// The cell builder builds its record and actor indexes during the world load.
    public static let prebuildIndexes = Self(rawValue: 1 << 4)
    /// Each plugin's FormID index is saved and read back next session.
    public static let recordIndexCache = Self(rawValue: 1 << 5)

    public static let all: Self = [
        .pluginReadAhead, .archiveReadAhead, .parallelRecords, .parallelFormIDIndex,
        .prebuildIndexes, .recordIndexCache
    ]

    private static let current = Atomic<UInt32>(all.rawValue)

    /// The switches in force. Read on any thread; set before a load starts.
    public static var active: Self {
        Self(rawValue: current.load(ordering: .relaxed))
    }

    public static func activate(_ options: Self) {
        current.store(options.rawValue, ordering: .relaxed)
    }

    public static func isOn(_ option: Self) -> Bool {
        active.contains(option)
    }
}
