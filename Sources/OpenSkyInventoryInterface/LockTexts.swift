// The words a lock shows: its level names, the prompt verb, and the two refusals.
// See docs/engine/locks.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct LockTexts: Equatable, Sendable {
    /// `sLockLevelName<suffix>`, by band.
    public var levelNames: [LockDifficulty: String]
    /// `sUnlock`: the prompt verb on a locked target.
    public var unlock = "Unlock"
    /// `sImpossibleLock`: a press on a lock that needs a key the player lacks.
    public var requiresKey = "sImpossibleLock"
    /// `sOutOfLockpicks`: a press with no lockpicks, or the last pick broken.
    public var outOfLockpicks = "sOutOfLockpicks"

    public static let vanilla = Self()

    public init() {
        levelNames = Dictionary(uniqueKeysWithValues: LockDifficulty.allCases.map { ($0, $0.name) })
    }

    public func name(of band: LockDifficulty) -> String {
        levelNames[band] ?? band.name
    }

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var settings = vanilla
        func word(_ editorID: String) -> String? {
            store.text(editorID).flatMap { text($0.text) }
        }
        for band in LockDifficulty.allCases {
            if let name = word("sLockLevelName\(band.settingSuffix)") {
                settings.levelNames[band] = name
            }
        }
        settings.unlock = word("sUnlock") ?? settings.unlock
        settings.requiresKey = word("sImpossibleLock") ?? settings.requiresKey
        settings.outOfLockpicks = word("sOutOfLockpicks") ?? settings.outOfLockpicks
        return settings
    }
}
