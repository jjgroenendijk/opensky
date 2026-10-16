// How health, magicka, and stamina regeneration slow in combat and pause after damage.
// The values are the install's; see docs/engine/actor-value-store.md, "Regeneration".

import Foundation

nonisolated public struct RegenerationSettings: Equatable, Sendable {
    /// `fCombatHealthRegenRateMult`. NPCs only: the player uses its own actor value.
    public var combatHealthMult: Float = 0
    /// `fCombatMagickaRegenRateMult`: 3% a second becomes 0.99% (UESP "Skyrim:Magicka").
    public var combatMagickaMult: Float = 0.33
    /// `fCombatStaminaRegenRateMult`: 5% a second becomes 1.75% (UESP "Skyrim:Stamina").
    public var combatStaminaMult: Float = 0.35
    /// `fDamagedHealthRegenDelay` and its siblings: seconds with no regeneration after damage.
    public var healthDelay: Float = 0.5
    public var magickaDelay: Float = 0.5
    public var staminaDelay: Float = 0.5
    /// `fDamagedAVRegenDelay`: the pause for a value whose own setting is missing.
    public var defaultDelay: Float = 1
    /// `bRegenNPCMagickaDuringCast`: false stops an NPC's magicka while it casts.
    public var npcMagickaDuringCast = false

    public static let vanilla = Self()
    /// The player's `Combat Health Regen Multiply` when no record sets it: 0.7, so
    /// 0.7% a second becomes 0.49% in combat (UESP "Skyrim:Health").
    public static let playerCombatHealthMult: Float = 0.7

    public init() {}

    /// The pause after damage to `kind`.
    public func delay(after kind: ActorValueKind) -> Float {
        switch kind {
        case .health: healthDelay
        case .magicka: magickaDelay
        case .stamina: staminaDelay
        }
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fCombatHealthRegenRateMult", into: &settings, \.combatHealthMult)
        store.read("fCombatMagickaRegenRateMult", into: &settings, \.combatMagickaMult)
        store.read("fCombatStaminaRegenRateMult", into: &settings, \.combatStaminaMult)
        store.read("fDamagedAVRegenDelay", into: &settings, \.defaultDelay)
        let fallback = store.number("fDamagedAVRegenDelay")
        settings.healthDelay = store.number("fDamagedHealthRegenDelay")
            ?? fallback ?? settings.healthDelay
        settings.magickaDelay = store.number("fDamagedMagickaRegenDelay")
            ?? fallback ?? settings.magickaDelay
        settings.staminaDelay = store.number("fDamagedStaminaRegenDelay")
            ?? fallback ?? settings.staminaDelay
        store.read("bRegenNPCMagickaDuringCast", into: &settings, \.npcMagickaDuringCast)
        return settings
    }
}
