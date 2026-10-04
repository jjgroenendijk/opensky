// The data locks and traps read at runtime: lockpicking tuning, the lockpick item,
// and the load-order hazard store. See docs/engine/locks.md and docs/engine/traps.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

nonisolated public struct LockTrapData: Sendable {
    /// GMST-derived, the documented numbers on a synthetic scene.
    public var lockpicking: LockpickingSettings
    /// The `LKPK` default object, relative to the base plugin like every inventory item.
    public var lockpickItem: FormID?
    /// Load-order HAZD index. Nil on a synthetic scene.
    public var hazards: HazardStore?

    public init(
        lockpicking: LockpickingSettings = .documentedDefaults,
        lockpickItem: FormID? = nil,
        hazards: HazardStore? = nil
    ) {
        self.lockpicking = lockpicking
        self.lockpickItem = lockpickItem
        self.hazards = hazards
    }

    public static func load(
        plugins: [(name: String, file: ESMFile)],
        baseFile: ESMFile,
        baseName: String,
        settings: GameSettingStore
    ) -> LockTrapData {
        LockTrapData(
            lockpicking: .resolve(store: settings),
            lockpickItem: DefaultObjectStore(plugins: [(baseName, baseFile)])
                .entry(tag: "LKPK")?.rawObject,
            hazards: HazardStore(plugins: plugins)
        )
    }
}

/// Lock and trap data. A synthetic scene answers the defaults.
nonisolated public protocol LockTrapDataProviding {
    var lockTrapData: LockTrapData { get }
}
