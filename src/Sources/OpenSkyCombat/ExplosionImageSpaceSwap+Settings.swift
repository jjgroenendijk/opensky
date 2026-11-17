// The game setting behind the explosion swap threshold.

public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated extension ExplosionImageSpaceSwap {
    /// The threshold from `store`; the modifier stays as `modifier`.
    public static func resolve(store: GameSettingStore, modifier: ReferenceKey? = nil) -> Self {
        var swap = Self(modifier: modifier)
        store.read("fExplosionImageSpaceSwapPower", into: &swap, \.threshold)
        return swap
    }
}
