// What the inventory coordinator works over in one loaded game. The app builds
// it from the load order; a test builds it from a fixture.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// The item runtime and the load order's data, rules, and texts for items.
@MainActor
public struct InventorySessionData {
    public let items: WorldItemRuntime
    /// Nil without an equipment index; equipping then refuses.
    public var equipment: EquipmentCatalog?
    /// Nil without recipe data.
    public var crafting: CraftingCatalog?
    public var alchemy = InventoryAlchemyData()
    public var locks = LockSessionData()
    /// Nil without a FACT and FLST index.
    public var vendors: VendorCoordinator?
    public var rules = InventoryRules()
    public var texts = InventoryTexts()

    public init(items: WorldItemRuntime) {
        self.items = items
    }
}

/// The MGEF index ingredient effects resolve through, and the lab's rules.
@MainActor
public struct InventoryAlchemyData {
    /// Nil leaves alchemy unavailable.
    public var effects: MagicEffectStore?
    /// The plugin ingredient EFID links are relative to.
    public var pluginName = FormIDResolver.loadOrderSpaceName
    public var settings = AlchemySettings.vanilla
    public var texts = AlchemyTexts.vanilla

    public init() {}
}

/// The load order's prices, reset intervals, and skill formulas for items.
nonisolated public struct InventoryRules: Equatable, Sendable {
    /// `fBarterMin` and `fBarterMax`.
    public var barterPricing = BarterPricing.vanilla
    /// The cell reset intervals a harvested plant waits for.
    public var cellReset = CellResetSettings.vanilla
    public var pickpocket = PickpocketSettings.vanilla
    /// The experience formulas a crafting session reports with.
    public var craftingSkillUse = CraftingSkillUseSettings.vanilla

    public init() {}
}

/// The load order's words for the item menus and notices.
nonisolated public struct InventoryTexts: Equatable, Sendable {
    public var menu = InventoryMenuTexts.vanilla
    /// The crosshair's verbs.
    public var activation = GameSettingTexts<ActivationText>.vanilla
    public var trade = TradeTexts.vanilla
    public var soul = SoulTexts.vanilla
    /// The quality names of an improved item.
    public var tempering = TemperingTexts.vanilla

    public init() {}
}

/// The load order's lockpicking rules and words.
nonisolated public struct LockSessionData: Equatable, Sendable {
    public var settings = LockpickingSettings.documentedDefaults
    public var texts = LockTexts.vanilla
    /// The `LKPK` default object. Nil keeps every lock shut to picking.
    public var lockpickItem: FormID?

    public init() {}
}

/// The features the inventory reports to. Each is held weakly.
@MainActor
public struct InventorySeams {
    public weak var recipeConditions: (any RecipeConditionChecking)?
    public weak var skillUses: (any SkillUseReporting)?
    /// Takes `AIPL`, `REMP`, `CRFT`, and the lock coordinator's `LOCK`.
    public weak var storyEvents: (any StoryEventReporting)?

    public init(
        recipeConditions: (any RecipeConditionChecking)? = nil,
        skillUses: (any SkillUseReporting)? = nil,
        storyEvents: (any StoryEventReporting)? = nil
    ) {
        self.recipeConditions = recipeConditions
        self.skillUses = skillUses
        self.storyEvents = storyEvents
    }
}
