public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyProgressionInterface

/// What the world adapters use of `MagicCoordinator`.
public protocol MagicPort: AnyObject {
    @discardableResult func reconcilePerkAbilities(
        on holder: ActorValueHolder,
        perks: any PerkAccess
    ) -> Bool
    func dispelEffects(on holder: ActorValueHolder, where predicate: (ActiveEffect) -> Bool) -> Int
    associatedtype ActiveEffectRuntime: ActiveEffectRuntimePort
    associatedtype ShoutMachine: ShoutMachinePort
    associatedtype CasterRuntime: CasterRuntimePort
    @discardableResult func applyPlacedPoison(
        _ poison: FormID,
        by caster: ReferenceKey,
        on target: ReferenceKey
    ) -> Int?
    @discardableResult func applySpellHit(_ hit: SpellHit) -> SpellHitReport
    @discardableResult func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit)
        -> WeaponEnchantmentReport?
    @discardableResult func applyWeaponEnhancement(
        attacker: ReferenceKey,
        target: ReferenceKey
    ) -> Int
    func applyWeaponPoison(_ hit: WeaponPoisonHit)
    var caster: CasterRuntime? { get }
    func cloakIsRunning(on holder: ActorValueHolder) -> Bool?
    var commanded: [CommandedActor] { get }
    @discardableResult func consumeMagicItem(_ item: FormID) -> MagicEffectActionOutcome
    var effects: ActiveEffectRuntime? { get }
    func elapseRestTime(seconds: Double)
    var enchantmentCacheReadout: EnchantmentCacheReadout { get }
    func enchantmentLine(of item: FormID, on holder: ActorValueHolder?) -> String?
    func enchantmentProfile(of item: FormID, on holder: InventoryHolder?) -> ItemEnchantmentProfile?
    @discardableResult func equipmentChanged(on holder: InventoryHolder) -> WornEnchantmentReport
    func grantAuthoredSpells(to holder: ActorValueHolder)
    func hasReadiedSpell(in hand: SpellHand) -> Bool
    var holdSettings: MagicHoldSettings { get }
    func influence(of key: ReferenceKey) -> ActorMagicInfluence
    var isPlayerTakingHealthDamage: Bool { get }
    func magicConditionResolution() -> MagicConditionResolution
    var magicLights: [MagicLight] { get }
    var magicMenuSpells: [MagicMenuSpell] { get }
    @discardableResult func noteDeath(
        of victim: ReferenceKey,
        killer: ReferenceKey?
    ) -> SoulTrapOutcome?
    func noteEffectsRestored()
    @discardableResult func npcShout(_ spell: ReferenceKey, by holder: ActorValueHolder) -> Bool
    func npcShouts(of holder: ActorValueHolder) -> [ResolvedShout]
    var playerGrabbedReference: ReferenceKey? { get }
    func playerKnownSpells() -> [ResolvedSpell]
    func playerStaff() -> (staff: HeldStaff, charge: EnchantmentCharge)?
    func raceEffectLinks(base: FormID, actor: ReferenceKey) -> [SpellHitEffectLinks]
    @discardableResult func readBook(_ item: FormID) -> CastingActionOutcome?
    @discardableResult func readyKnownSpell(
        at index: Int,
        in hand: SpellHand
    ) -> CastingActionOutcome
    /// Reads `item` and gives the line the outcome shows, or nil for no spell tome.
    func readBookLine(_ item: FormID) -> String?
    /// Readies a known spell and gives the line the outcome shows.
    func readyKnownSpellLine(at index: Int, in hand: SpellHand) -> String
    func restoreShoutCooldown(_ seconds: Float)
    var shoutMachine: ShoutMachine { get }
    var shouts: [ReferenceKey: ResolvedShout] { get }
    func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>)
    var summonFades: [ReferenceKey: Float] { get }
    func takeCommands() -> [MagicCommand]
    @discardableResult func trapSoul(
        of victim: ReferenceKey,
        by caster: ReferenceKey
    ) -> SoulTrapOutcome

    func advanceCasting(
        _ intent: CastingIntent,
        isPlayerControlled: Bool,
        events: [String],
        weaponsDrawn: Bool?
    ) -> [MagicCommand]
    func advanceEffects(delta: Float) -> [MagicCommand]

    func advanceShout(
        held: Bool,
        delta: Float,
        events: [String],
        isPlayerControlled: Bool
    ) -> [MagicCommand]
    var timeScales: MagicTimeScales { get }

    func wantsCast(_ hand: SpellHand) -> Bool
}

/// The default arguments a protocol requirement cannot carry.
extension MagicPort {
    @discardableResult public func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        enchantmentProfile(of: item, on: nil)
    }
}
