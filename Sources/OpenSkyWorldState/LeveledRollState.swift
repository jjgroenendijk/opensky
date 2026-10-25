// The player level a placed actor's or container's leveled lists roll at. The
// cell freezes it when it first loads, and a cell reset rolls again. See
// docs/engine/leveled-lists.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct LeveledRollState: WorldStateComponent, Hashable, Sendable {
    public var playerLevel: Int

    public static var componentKind: WorldStateComponentKind {
        .leveledRoll
    }

    public init(playerLevel: Int) {
        self.playerLevel = playerLevel
    }
}

nonisolated extension WorldStateComponentKind {
    /// The build already rolled at the level the freeze writes, so the write
    /// rebuilds nothing.
    public static let leveledRoll = Self(
        rawValue: "leveledRoll",
        order: 44,
        affectsCellBuild: false
    )
}

extension WorldStateStore {
    /// The level `key` froze, or nil when its cell has not frozen one.
    public func frozenLeveledLevel(of key: ReferenceKey) -> Int? {
        component(LeveledRollState.self, for: key)?.playerLevel
    }

    /// The roll of the placed actor `key` of `base`, at the level its cell froze.
    public func leveledRoll(
        of key: ReferenceKey, base: FormID, with roller: LeveledListRoller
    ) -> LeveledRoll {
        roller.roll(for: key, base: base, cell: nil, frozenLevel: frozenLeveledLevel(of: key))
    }
}
