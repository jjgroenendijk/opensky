// Setting values one benchmark run forces for the whole process. Every store
// reads them over the saved file and writes nothing while they hold, so the
// player's own settings come back unchanged after the run.

import Synchronization

nonisolated public enum PlayerSettingsOverrides {
    private static let values = Mutex<[PlayerSettingID: Double]>([:])

    public static var current: [PlayerSettingID: Double] {
        values.withLock { $0 }
    }

    public static var isActive: Bool {
        !current.isEmpty
    }

    /// Set once at launch, before the first store opens.
    public static func set(_ overrides: [PlayerSettingID: Double]) {
        values.withLock { $0 = overrides }
    }
}
