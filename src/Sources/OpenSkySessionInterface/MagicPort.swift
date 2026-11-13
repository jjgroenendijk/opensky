public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyProgressionInterface

/// What the world adapters use of `MagicCoordinator`.
public protocol MagicPort: AnyObject {
    associatedtype FrameStep: MagicFrameStepPort
    var frameStep: FrameStep { get }
    associatedtype ItemUse: MagicItemUsePort
    var itemUse: ItemUse { get }
    associatedtype WeaponEnchantments: MagicWeaponEnchantmentsPort
    var weaponEnchantments: WeaponEnchantments { get }
    associatedtype ShoutVoice: MagicShoutVoicePort
    var shoutVoice: ShoutVoice { get }
    associatedtype SoulTrapping: MagicSoulTrappingPort
    var soulTrapping: SoulTrapping { get }
    associatedtype MenuLines: MagicMenuLinesPort
    var menuLines: MenuLines { get }
    associatedtype Enchanter: MagicEnchanterPort
    var enchanter: Enchanter { get }
    associatedtype MagicMenu: MagicMenuListPort
    var magicMenu: MagicMenu { get }
    associatedtype WorldArchetypeActions: MagicWorldArchetypesPort
    var worldArchetypeActions: WorldArchetypeActions { get }
    associatedtype ArchetypeActions: MagicArchetypeActionsPort
    var archetypeActions: ArchetypeActions { get }

    associatedtype ActiveEffectRuntime: ActiveEffectRuntimePort
    associatedtype ShoutMachine: ShoutMachinePort
    associatedtype CasterRuntime: CasterRuntimePort
    @discardableResult func applySpellHit(_ hit: SpellHit) -> SpellHitReport
    var caster: CasterRuntime? { get }
    var commanded: [CommandedActor] { get }
    var effects: ActiveEffectRuntime? { get }
    var holdSettings: MagicHoldSettings { get }
    func magicConditionResolution() -> MagicConditionResolution
    var magicLights: [MagicLight] { get }
    func noteEffectsRestored()
    var playerGrabbedReference: ReferenceKey? { get }
    func playerKnownSpells() -> [ResolvedSpell]
    func playerStaff() -> (staff: HeldStaff, charge: EnchantmentCharge)?
    func raceEffectLinks(base: FormID, actor: ReferenceKey) -> [SpellHitEffectLinks]
    var shoutMachine: ShoutMachine { get }
    var shouts: [ReferenceKey: ResolvedShout] { get }
    var summonFades: [ReferenceKey: Float] { get }

    var timeScales: MagicTimeScales { get }

    func wantsCast(_ hand: SpellHand) -> Bool
}

/// The frame step: effects, casting, and the commands they leave.
public protocol MagicFrameStepPort {
    func elapseRestTime(seconds: Double)
    func takeCommands() -> [MagicCommand]
    func advanceCasting(
        _ intent: CastingIntent,
        isPlayerControlled: Bool,
        events: [String],
        weaponsDrawn: Bool?
    ) -> [MagicCommand]
    func advanceEffects(delta: Float) -> [MagicCommand]
}

/// Consuming magic items, authored spells, and dispelling.
public protocol MagicItemUsePort {
    @discardableResult func reconcilePerkAbilities(
        on holder: ActorValueHolder,
        perks: any PerkAccess
    ) -> Bool
    func dispelEffects(on holder: ActorValueHolder, where predicate: (ActiveEffect) -> Bool) -> Int
    @discardableResult func consumeMagicItem(_ item: FormID) -> MagicEffectActionOutcome
    func grantAuthoredSpells(to holder: ActorValueHolder)
    func hasReadiedSpell(in hand: SpellHand) -> Bool
}

/// Weapon and worn enchantments, and poisons.
public protocol MagicWeaponEnchantmentsPort {
    @discardableResult func applyPlacedPoison(
        _ poison: FormID,
        by caster: ReferenceKey,
        on target: ReferenceKey
    ) -> Int?
    @discardableResult func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit)
        -> WeaponEnchantmentReport?
    func applyWeaponPoison(_ hit: WeaponPoisonHit)
    var enchantmentCacheReadout: EnchantmentCacheReadout { get }
    func enchantmentLine(of item: FormID, on holder: ActorValueHolder?) -> String?
    func enchantmentProfile(of item: FormID, on holder: InventoryHolder?) -> ItemEnchantmentProfile?
    @discardableResult func equipmentChanged(on holder: InventoryHolder) -> WornEnchantmentReport
    func chargePercent(of item: FormID) -> Float?
    func rechargeOffer(for item: FormID) -> RechargeOffer?
    @discardableResult func recharge(_ item: FormID, gemIndex: Int) -> Bool
}

/// Shouts the player and NPCs voice.
public protocol MagicShoutVoicePort {
    @discardableResult func npcShout(_ spell: ReferenceKey, by holder: ActorValueHolder) -> Bool
    func npcShouts(of holder: ActorValueHolder) -> [ResolvedShout]
    func restoreShoutCooldown(_ seconds: Float)
    func advanceShout(
        held: Bool,
        delta: Float,
        events: [String],
        isPlayerControlled: Bool
    ) -> [MagicCommand]
}

/// Deaths and the souls they fill gems with.
public protocol MagicSoulTrappingPort {
    @discardableResult func noteDeath(
        of victim: ReferenceKey,
        killer: ReferenceKey?
    ) -> SoulTrapOutcome?
    @discardableResult func trapSoul(
        of victim: ReferenceKey,
        by caster: ReferenceKey
    ) -> SoulTrapOutcome
}

/// The arcane enchanter's menu.
public protocol MagicEnchanterPort {
    var enchanterChoices: EnchanterChoices { get }
    func disenchant(_ item: FormID) -> EnchanterAnswer
    func refusal(of selection: EnchanterSelection) -> String?
    func enchant(_ selection: EnchanterSelection) -> EnchanterAnswer
}

/// The lines a menu shows for a read book or a readied spell.
public protocol MagicMenuLinesPort {
    /// Reads `item` and gives the line the outcome shows, or nil for no spell tome.
    func readBookLine(_ item: FormID) -> String?
    /// Readies a known spell and gives the line the outcome shows.
    func readyKnownSpellLine(at index: Int, in hand: SpellHand) -> String
}

/// What the Magic menu lists.
public protocol MagicMenuListPort {
    var isPlayerTakingHealthDamage: Bool { get }
    var magicMenuSpells: [MagicMenuSpell] { get }
    /// The tab titles in the menu's order.
    var magicMenuCategoryOrder: [String] { get }
    var magicMenuActiveEffects: [String] { get }
    var magicMenuActiveEffectsTitle: String { get }
}

/// Effects that act on the world when a spell or a weapon lands.
public protocol MagicWorldArchetypesPort {
    @discardableResult func applyWeaponEnhancement(
        attacker: ReferenceKey,
        target: ReferenceKey
    ) -> Int
    func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>)
}

/// What the running effects do to an actor.
public protocol MagicArchetypeActionsPort {
    func cloakIsRunning(on holder: ActorValueHolder) -> Bool?
    func influence(of key: ReferenceKey) -> ActorMagicInfluence
}

/// The default arguments a protocol requirement cannot carry.
extension MagicWeaponEnchantmentsPort {
    @discardableResult public func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        enchantmentProfile(of: item, on: nil)
    }
}
