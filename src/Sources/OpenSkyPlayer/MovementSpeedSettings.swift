// The game settings that scale how fast an actor moves: worn weight, the in-between gaits,
// and the default turn rate. See docs/engine/walk-mode.md#speed.

public import OpenSkyGameData

nonisolated public struct MovementSpeedSettings: Equatable, Sendable {
    /// `fMoveEncumEffect`: the share of speed full weight takes with a weapon drawn.
    public var encumbranceEffect: Float = 0.3
    /// `fMoveEncumEffectNoWeapon`: the same share with the weapon away.
    public var encumbranceEffectNoWeapon: Float = 0.15
    /// `fMoveWeightMin` (no plugin sets it) and `fMoveWeightMax`: the weight range.
    public var weightMin: Float = 0
    public var weightMax: Float = 115
    /// `fFastWalkInterpolationBetweenWalkAndRun` and `fJogInterpolationBetweenWalkAndRun`.
    public var fastWalkBlend: Float = 0.15
    public var jogBlend: Float = 0.65
    /// `fActorDefaultTurningSpeed`: radians a second for a walking actor.
    public var defaultTurnRate: Float = 6.2832

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fMoveEncumEffect", into: &settings, \.encumbranceEffect)
        store.read("fMoveEncumEffectNoWeapon", into: &settings, \.encumbranceEffectNoWeapon)
        store.read("fMoveWeightMin", into: &settings, \.weightMin)
        store.read("fMoveWeightMax", into: &settings, \.weightMax)
        store.read("fFastWalkInterpolationBetweenWalkAndRun", into: &settings, \.fastWalkBlend)
        store.read("fJogInterpolationBetweenWalkAndRun", into: &settings, \.jogBlend)
        store.read("fActorDefaultTurningSpeed", into: &settings, \.defaultTurnRate)
        return settings
    }

    /// The speed share left under `weight`: 1 - effect x (min(weight, max) + min) / (max - min).
    /// With vanilla values, 115 worn weight and a drawn weapon leave 0.7.
    public func encumbranceFactor(weight: Float, weaponDrawn: Bool) -> Float {
        let range = weightMax - weightMin
        guard range > 0, weight.isFinite else { return 1 }
        let effect = weaponDrawn ? encumbranceEffect : encumbranceEffectNoWeapon
        let share = (min(max(weight, 0), weightMax) + weightMin) / range
        return max(0, 1 - effect * share)
    }

    /// The speed scale of the player's gaits: worn weight, then `SpeedMult` over 100.
    public func speedScale(wornWeight: Float, weaponDrawn: Bool, speedMult: Float) -> Float {
        let mult = speedMult.isFinite ? max(0, speedMult) / 100 : 1
        return encumbranceFactor(weight: wornWeight, weaponDrawn: weaponDrawn) * mult
    }
}
