// The shell of the inventory domain: owns the world-item and equipment
// runtimes, the open container session, and the readout lines. The
// rules live in `InventoryCore`. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

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
    public private(set) var session: ContainerSession?
    /// Captured on open, because the cell holding the container may be evicted
    /// while it is still open.
    public private(set) var sessionName: String?
    public private(set) var lastAction = ItemActionOutcome.idle
    /// Kept apart from `lastAction`, so a grant does not overwrite the
    /// take and drop readout on the other readout.
    public private(set) var lastGrant = GrantActionOutcome.idle
    /// The NPC by default: an equip is only visible on a rendered actor.
    public var inspectionTarget = EquipmentTargetSelector.nearestActor
    /// Nil without a FACT and FLST index.
    public let vendors: VendorCoordinator?
    /// Lock state, keys, and lockpicking, over the same world-item runtime.
    public let locks: LockCoordinator
    /// Nil without recipe data.
    public let craftingCatalog: CraftingCatalog?
    /// At most one station is in use at a time.
    public internal(set) var crafting: CraftingSession?
    public internal(set) var lastCraft = CraftingActionOutcome.idle
    weak let recipeConditions: (any RecipeConditionChecking)?
    weak let skillUses: (any SkillUseReporting)?
    /// The experience formulas a crafting session reports with.
    public let craftingSkillUse: CraftingSkillUseSettings
    public let menuTexts: InventoryMenuTexts
    /// The crosshair's verbs.
    public let activationTexts: GameSettingTexts<ActivationText>
    public let tradeTexts: TradeTexts
    public let pickpocketSettings: PickpocketSettings
    public let soulTexts: SoulTexts
    /// The quality names of an improved item.
    public let temperingTexts: TemperingTexts
    /// The load order's cell reset intervals, which a harvested plant waits for.
    public let cellReset: CellResetSettings
    /// The ingredients chosen at the open alchemy lab, in the order chosen. Nil when no
    /// lab is open.
    public internal(set) var alchemySelection: [FormID]?
    public internal(set) var lastAlchemy = AlchemyActionOutcome.idle
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
        cellReset = rules.cellReset
        pickpocketSettings = rules.pickpocket
        craftingSkillUse = rules.craftingSkillUse
        let texts = data?.texts ?? InventoryTexts()
        menuTexts = texts.menu
        activationTexts = texts.activation
        tradeTexts = texts.trade
        soulTexts = texts.soul
        temperingTexts = texts.tempering
        let alchemy = data?.alchemy ?? InventoryAlchemyData()
        magicEffects = alchemy.effects
        magicItemPlugin = alchemy.pluginName
        alchemySettings = alchemy.settings
        alchemyTexts = alchemy.texts
        registerCreatedPotions()
    }

    /// The use key: take a loose item, search a container, harvest a plant, or
    /// use a crafting station. Other actions belong to other domains and pass through.
    public func handleInteraction(_ action: InteractionAction) -> [InventoryCommand] {
        switch action {
        case .take:
            note(takeInteractionTarget())
        case .search:
            note(openInteractionTargetContainer())
        case .harvest:
            return harvestInteractionTarget().commands
        case .use:
            if let station = world.crosshairInteraction.flatMap(CraftingActivationEvent.init) {
                openCraftingSession(station)
            }
        default:
            break
        }
        return []
    }

    // MARK: - Item actions

    @discardableResult
    public func takeInteractionTarget() -> ItemActionOutcome {
        guard runtime != nil else { return .unavailable }
        guard let interaction = world.crosshairInteraction else {
            return .nothingUnderCrosshair(verb: "take")
        }
        return take(interaction)
    }

    /// Takes the item behind `interaction`, such as a book read where it lies.
    @discardableResult
    public func take(_ interaction: PlacedInteraction) -> ItemActionOutcome {
        guard let runtime else { return .unavailable }
        do {
            let outcome = try runtime.take(interaction)
            storyEvents?.reportStoryEvent(.addItem(
                outcome.item, from: nil, owner: nil, how: outcome.stolen ? .steal : .pickUp
            ))
            return note(.took(count: outcome.count, item: interaction.name))
        } catch {
            return note(.failed(action: "Take", reason: String(describing: error)))
        }
    }

    @discardableResult
    public func openInteractionTargetContainer() -> ItemActionOutcome {
        guard let runtime else { return .unavailable }
        guard let interaction = world.crosshairInteraction else {
            return .nothingUnderCrosshair(verb: "search")
        }
        // Closing first keeps one session live and leaves the previous
        // container's `isOpen` false.
        session?.close()
        do {
            let opened = try runtime.openContainer(interaction)
            session = opened
            sessionName = interaction.name
            return note(.opened(container: interaction.name, items: opened.totalCount))
        } catch {
            session = nil
            sessionName = nil
            return note(.failed(action: "Search", reason: String(describing: error)))
        }
    }

    @discardableResult
    public func closeOpenContainer() -> ItemActionOutcome {
        guard let session else { return .noContainer }
        session.close()
        self.session = nil
        sessionName = nil
        return note(.closed)
    }

    /// Drops `item`, or the first carried stack when `item` is nil.
    @discardableResult
    public func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome {
        guard let runtime else { return .unavailable }
        let carried = runtime.inventory.inventory(of: runtime.player).stacks
        guard let target = item ?? carried.first?.item else { return .nothingToDrop }
        guard let placement = world.dropPlacement() else { return .noDropCell }
        do {
            try runtime.drop(target, count: count, at: placement)
            storyEvents?.reportStoryEvent(.removeItem(
                target, reference: nil, owner: nil, how: .dropped
            ))
            return note(.dropped(count: count, item: name(of: target)))
        } catch {
            return note(.failed(action: "Drop", reason: String(describing: error)))
        }
    }

    /// A dead actor's drawn weapon falls to `placement`, out of its inventory.
    /// - Returns: the item dropped, or nil when the actor holds no drawn weapon.
    @discardableResult
    public func dropWeapon(of holder: InventoryHolder, at placement: DropPlacement) -> FormID? {
        guard
            let runtime, let equipment,
            let weapon = equipment.equipped(on: holder).first(where: { item in
                equipment.catalog.item(item)?.animationType != nil
                    && equipment.catalog.item(item)?.occupancy.hands.contains(.rightHand) == true
            }),
            (try? runtime.drop(weapon, count: 1, from: holder, at: placement)) != nil
        else { return nil }
        storyEvents?.reportStoryEvent(.removeItem(
            weapon, reference: nil, owner: nil, how: .dropped
        ))
        return weapon
    }

    // MARK: - Names

    public func name(of item: FormID) -> String {
        InventoryCore.displayName(
            of: item, definition: runtime?.inventory.baselines.items.definition(item)
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
            .map { soulTexts.name(of: SoulLevel(rawValue: $0.soul)) }
        let filled = souls.isEmpty ? nil : "filled copies: " + souls.joined(separator: ", ")
        let lines = [runtime.inventory.baselines.items.familyDetail(item, souls: soulTexts), filled]
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
