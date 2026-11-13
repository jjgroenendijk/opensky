// The shell of the inventory domain: owns the world-item and equipment
// runtimes, the open container session, and the readout lines. The
// rules live in `InventoryCore`. See docs/engine/coordinators.md.

public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

/// Owns the inventory runtimes and reads the world through `InventoryWorld`.
/// Without game data every runtime is nil, and each action then says so.
@MainActor
public final class InventoryCoordinator {
    public let runtime: WorldItemRuntime?
    /// Nil without an equipment catalog.
    public let equipment: EquipmentRuntime?
    /// The load order's `fBarterMin` and `fBarterMax`, else the vanilla values.
    public let barterPricing: BarterPricing
    /// At most one container is open from the Items readout at a time.
    public internal(set) var session: ContainerSession?
    /// Captured on open, because the cell holding the container may be evicted
    /// while it is still open.
    public internal(set) var sessionName: String?
    var lastAction = ItemActionOutcome.idle
    /// Kept apart from `lastAction`, so a grant does not overwrite the
    /// take and drop readout on the other readout.
    var lastGrant = GrantActionOutcome.idle
    /// The NPC by default: an equip is only visible on a rendered actor.
    var inspectionTarget = EquipmentTargetSelector.nearestActor
    /// Nil without a FACT and FLST index.
    public let vendors: VendorCoordinator?
    /// Lock state, keys, and lockpicking, over the same world-item runtime.
    public let locks: LockCoordinator
    /// Nil without recipe data.
    public let craftingCatalog: CraftingCatalog?
    /// At most one station is in use at a time.
    public internal(set) var crafting: CraftingSession?
    var lastCraft = CraftingActionOutcome.idle
    weak let recipeConditions: (any RecipeConditionChecking)?
    weak let skillUses: (any SkillUseReporting)?
    /// The experience formulas a crafting session reports with.
    public let craftingSkillUse: CraftingSkillUseSettings
    /// The menu, crosshair, trade, soul and tempering words.
    public let texts: InventoryTexts
    public let pickpocketSettings: PickpocketSettings
    /// The ingredients chosen at the open alchemy lab, in the order chosen. Nil when no
    /// lab is open.
    public internal(set) var alchemySelection: [FormID]?
    var lastAlchemy = AlchemyActionOutcome.idle
    public let alchemySettings: AlchemySettings
    public let alchemyTexts: AlchemyTexts
    /// The MGEF index ingredient effects resolve through. Nil leaves alchemy unavailable.
    public let magicEffects: MagicEffectStore?
    /// The plugin ingredient EFID links are relative to.
    let magicItemPlugin: String

    let world: any InventoryWorld
    /// Takes `AIPL`, `REMP`, and `CRFT`. The lock coordinator has its own.
    public weak let storyEvents: (any StoryEventReporting)?

    /// Without `data` there is no game, and every action says it is unavailable.
    public init(
        world: any InventoryWorld,
        lockWorld: any LockWorld,
        data: InventorySessionData?,
        seams: InventorySeams = InventorySeams()
    ) {
        self.world = world
        runtime = data?.items
        equipment = data.flatMap { data in
            data.equipment.map { EquipmentRuntime(inventory: data.items.inventory, catalog: $0) }
        }
        locks = LockCoordinator(
            world: lockWorld,
            items: data?.items,
            data: data?.locks ?? LockSessionData(),
            storyEvents: seams.storyEvents
        )
        vendors = data?.vendors
        craftingCatalog = data?.crafting
        recipeConditions = seams.recipeConditions
        skillUses = seams.skillUses
        storyEvents = seams.storyEvents
        let rules = data?.rules ?? InventoryRules()
        barterPricing = rules.barterPricing
        pickpocketSettings = rules.pickpocket
        craftingSkillUse = rules.craftingSkillUse
        texts = data?.texts ?? InventoryTexts()
        let alchemy = data?.alchemy ?? InventoryAlchemyData()
        magicEffects = alchemy.effects
        magicItemPlugin = alchemy.pluginName
        alchemySettings = alchemy.settings
        alchemyTexts = alchemy.texts
        alchemyLab.registerCreatedPotions()
    }

    // MARK: - Names

    public func name(of item: FormID) -> String {
        InventoryCore.displayName(
            of: item, definition: runtime?.inventory.baselines.items.definition(item),
            missing: texts.missingName
        )
    }

    public func readout(_ stacks: [InventoryStack]) -> [ItemStackReadout] {
        stacks.map {
            ItemStackReadout(
                item: $0.item,
                count: $0.count,
                name: name(of: $0.item),
                stolen: $0.stolen,
                detail: detail(of: $0.item)
            )
        }
    }

    /// The record's family line, then the souls the player's own copies hold.
    private func detail(of item: FormID) -> String? {
        guard let runtime else { return nil }
        let souls = runtime.inventory.copies(of: item, in: runtime.player)
            .filter { $0.soul != 0 }
            .map { texts.soul.name(of: SoulLevel(rawValue: $0.soul)) }
        let filled = souls.isEmpty ? nil : "filled copies: " + souls.joined(separator: ", ")
        let lines = [
            runtime.inventory.baselines.items.familyDetail(item, souls: texts.soul),
            filled
        ]
        .compactMap(\.self)
        return lines.isEmpty ? nil : lines.joined(separator: "; ")
    }

    @discardableResult
    func note(_ outcome: ItemActionOutcome) -> ItemActionOutcome {
        lastAction = outcome
        return outcome
    }

    func noteGrant(_ outcome: GrantActionOutcome) -> GrantActionOutcome {
        lastGrant = outcome
        return outcome
    }
}

extension InventoryCoordinator {
    public var isCrafting: Bool {
        crafting != nil
    }
}

extension InventoryCoordinator {
    public var itemActions: ItemActions {
        ItemActions(coordinator: self)
    }

    public var alchemyLab: AlchemyLab {
        AlchemyLab(coordinator: self)
    }

    public var craftingBench: CraftingBench {
        CraftingBench(coordinator: self)
    }

    public var craftingReadout: CraftingReadout {
        CraftingReadout(coordinator: self)
    }

    public var containerTrade: ContainerTrade {
        ContainerTrade(coordinator: self)
    }

    public var teammateTrades: TeammateTrades {
        TeammateTrades(coordinator: self)
    }

    public var scriptItems: ScriptItems {
        ScriptItems(coordinator: self)
    }

    public var pickpocketing: Pickpocketing {
        Pickpocketing(coordinator: self)
    }

    public var itemPanels: ItemPanels {
        ItemPanels(coordinator: self)
    }

    public var consumables: Consumables {
        Consumables(coordinator: self)
    }

    public var itemCards: ItemCards {
        ItemCards(coordinator: self)
    }

    public var itemConditions: ItemConditions {
        ItemConditions(coordinator: self)
    }

    public var equipmentChanges: EquipmentChanges {
        EquipmentChanges(coordinator: self)
    }

    public var armourWeights: ArmourWeights {
        ArmourWeights(coordinator: self)
    }

    public var followerTakes: FollowerTakes {
        FollowerTakes(coordinator: self)
    }

    public var deathItems: DeathItems {
        DeathItems(coordinator: self)
    }

    public var favouriteItems: FavouriteItems {
        FavouriteItems(coordinator: self)
    }

    public var readoutLines: ReadoutLines {
        ReadoutLines(coordinator: self)
    }

    /// Take, search, drop, and close: the item actions of the use key and the Items readout.
    public struct ItemActions {
        let coordinator: InventoryCoordinator
    }

    /// The alchemy lab: ingredients, their known effects, and brewing.
    public struct AlchemyLab {
        let coordinator: InventoryCoordinator
    }

    /// The crafting stations: open, craft, temper, and close.
    public struct CraftingBench {
        let coordinator: InventoryCoordinator
    }

    /// The crafting readout and the quality names of improved items.
    public struct CraftingReadout {
        let coordinator: InventoryCoordinator
    }

    /// Moving items between holders: take all, transfer, and the holder of a container.
    public struct ContainerTrade {
        let coordinator: InventoryCoordinator

        public var tradeTexts: TradeTexts {
            coordinator.texts.trade
        }
    }

    /// Trading with a teammate: what they carry, refuse, and wear.
    public struct TeammateTrades {
        let coordinator: InventoryCoordinator
    }

    /// The inventory calls Papyrus scripts make.
    public struct ScriptItems {
        let coordinator: InventoryCoordinator
    }

    /// Stealing from and planting on an actor.
    public struct Pickpocketing {
        let coordinator: InventoryCoordinator
    }

    /// The inventory readouts: owners, equipment, and grants.
    public struct ItemPanels {
        let coordinator: InventoryCoordinator
    }

    /// Using an item: eating, drinking, and applying a poison.
    public struct Consumables {
        let coordinator: InventoryCoordinator
    }

    /// The card an item shows in the menus.
    public struct ItemCards {
        let coordinator: InventoryCoordinator

        public var menuTexts: InventoryMenuTexts {
            coordinator.texts.menu
        }
    }

    /// What condition functions read from inventories.
    public struct ItemConditions {
        let coordinator: InventoryCoordinator
    }

    /// Equipping and unequipping items.
    public struct EquipmentChanges {
        let coordinator: InventoryCoordinator
    }

    /// The weight the player carries and wears.
    public struct ArmourWeights {
        let coordinator: InventoryCoordinator
    }

    /// Followers picking items up and taking from containers.
    public struct FollowerTakes {
        let coordinator: InventoryCoordinator
    }

    /// The item an actor drops on death.
    public struct DeathItems {
        let coordinator: InventoryCoordinator
    }

    /// The player's favourites and hotkeys.
    public struct FavouriteItems {
        let coordinator: InventoryCoordinator
    }

    /// The sentences the alchemy and crafting readouts show.
    public struct ReadoutLines {
        let coordinator: InventoryCoordinator
    }
}
