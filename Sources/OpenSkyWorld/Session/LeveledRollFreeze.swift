// Freezes the player level each placed actor and container rolls its leveled lists
// at, when its cell joins the live world. The level stays until the cell resets.
// See docs/engine/leveled-lists.md.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyWorldState

@MainActor
public enum LeveledRollFreeze {
    /// Freezes `level` on each reference of `scene` that `rolls` and has no level yet.
    /// - Returns: the keys it froze.
    @discardableResult
    public static func freeze(
        _ scene: CellScene, level: Int, in store: WorldStateStore,
        rolls: (RuntimeReferenceEntry) -> Bool
    ) -> [ReferenceKey] {
        var frozen: [ReferenceKey] = []
        for entry in scene.references.sortedEntries()
            where store.frozenLeveledLevel(of: entry.key) == nil && rolls(entry)
        {
            store.set(LeveledRollState(playerLevel: level), for: entry.key, in: scene.location)
            frozen.append(entry.key)
        }
        return frozen
    }
}
