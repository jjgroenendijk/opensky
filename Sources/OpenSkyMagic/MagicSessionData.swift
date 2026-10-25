// What the magic coordinator works over in one loaded game. The app builds it
// from the load order; a test builds it from a fixture.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyGameData
import OpenSkyMagicInterface

/// The magic runtimes' inputs and the load order's magic rules and texts.
@MainActor
public struct MagicSessionData {
    /// Nil without an MGEF index; then no effect runs.
    public var effects: MagicEffectsData?
    /// Nil without a SPEL index; then nobody casts.
    public var casting: MagicCastingData?
    public var enchantments: EnchantmentStore?
    public var shouts: ShoutStore?
    public var rules = MagicRules()
    public var texts = MagicSessionTexts()

    public init() {}
}

/// The active-effect runtime's inputs.
@MainActor
public struct MagicEffectsData {
    public let values: any ActorValueAccess
    public let store: MagicEffectStore
    /// The plugin every magic item's EFID links are relative to.
    public let pluginName: String
    public let conditionRegistry: ConditionFunctionRegistry

    public init(
        values: any ActorValueAccess,
        store: MagicEffectStore,
        pluginName: String,
        conditionRegistry: ConditionFunctionRegistry
    ) {
        self.values = values
        self.store = store
        self.pluginName = pluginName
        self.conditionRegistry = conditionRegistry
    }
}

/// The caster runtime's inputs.
@MainActor
public struct MagicCastingData {
    public let spellbook: SpellbookRuntime
    public let values: any ActorValueAccess
    /// The plugin an actor's `SPLO` links are relative to.
    public let spellPluginName: String?
    public let baselines: ActorSpellBaselineResolver?

    public init(
        spellbook: SpellbookRuntime,
        values: any ActorValueAccess,
        spellPluginName: String?,
        baselines: ActorSpellBaselineResolver?
    ) {
        self.spellbook = spellbook
        self.values = values
        self.spellPluginName = spellPluginName
        self.baselines = baselines
    }
}

/// The load order's magic formulas and limits.
nonisolated public struct MagicRules: Equatable, Sendable {
    public var spellCost = SpellCostSettings.vanilla
    public var soulTrap = SoulTrapSettings.vanilla
    public var holds = MagicHoldSettings.vanilla
    public var enchanting = EnchantingSettings.vanilla
    public var shouts = ShoutSettings.vanilla
    public var runes = RuneSettings.vanilla

    public init() {}
}

/// The load order's words for spells, refused casts, and souls.
nonisolated public struct MagicSessionTexts: Equatable, Sendable {
    /// The spell words the spellcasting readout shows.
    public var magic = MagicTexts.vanilla
    public var castNotices = GameSettingTexts<CastNoticeText>.vanilla
    public var souls = SoulTexts.vanilla

    public init() {}
}
