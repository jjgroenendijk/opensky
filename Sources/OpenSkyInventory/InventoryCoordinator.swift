// The shell of the inventory domain: owns the world-item and equipment
// runtimes, the open container session, and the panel readout lines. The
// rules live in `InventoryCore`. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Owns the inventory runtimes and reads the world through `InventoryWorld`.
/// Every runtime stays nil without game data, and each action then says so.
@MainActor
public final class InventoryCoordinator {
    /// Nil until `wire`.
    public private(set) var runtime: WorldItemRuntime?
    /// Nil until `wire` gets an equipment catalog.
    public private(set) var equipment: EquipmentRuntime?
    /// The load order's `fBarterMin` and `fBarterMax`, else the vanilla values.
    public private(set) var barterPricing = BarterPricing.vanilla
    /// At most one container is open from the Items panel at a time.
    public private(set) var session: ContainerSession?
    /// Captured on open, because the cell holding the container may be evicted
    /// while it is still open.
    public private(set) var sessionName: String?
    public private(set) var lastAction = ItemActionOutcome.idle
    /// Kept apart from `lastAction`, so a grant does not overwrite the
    /// take and drop readout on the other panel.
    public private(set) var lastGrant = GrantActionOutcome.idle
    /// The NPC by default: an equip is only visible on a rendered actor.
    public var inspectionTarget = EquipmentTargetSelector.nearestActor
    /// Nil without a FACT and FLST index.
    public var vendors: VendorCoordinator?
    /// Lock state, keys, and lockpicking, over the same world-item runtime.
    public let locks: LockCoordinator
    /// Nil without recipe data.
    public internal(set) var craftingCatalog: CraftingCatalog?
    /// At most one station is in use at a time.
    public internal(set) var crafting: CraftingSession?
    public internal(set) var lastCraft = CraftingActionOutcome.idle
    weak var recipeConditions: (any RecipeConditionChecking)?
    weak var skillUses: (any SkillUseReporting)?
    /// The experience formulas a crafting session reports with.
    public var craftingSkillUse = CraftingSkillUseSettings.vanilla
    public var menuTexts = InventoryMenuTexts.vanilla
    /// The crosshair's verbs.
    public var activationTexts = GameSettingTexts<ActivationText>.vanilla
    public var tradeTexts = TradeTexts.vanilla
    public var pickpocketSettings = PickpocketSettings.vanilla
    public var soulTexts = SoulTexts.vanilla
    /// The quality names of an improved item.
    public var temperingTexts = TemperingTexts.vanilla
    /// The load order's cell reset intervals, which a harvested plant waits for.
    public private(set) var cellReset = CellResetSettings.vanilla
    /// The ingredients chosen at the open alchemy lab, in the order chosen. Nil when no
    /// lab is open.
    public internal(set) var alchemySelection: [FormID]?
    public internal(set) var lastAlchemy = AlchemyActionOutcome.idle
    public var alchemySettings = AlchemySettings.vanilla
    public var alchemyTexts = AlchemyTexts.vanilla
    /// The MGEF index ingredient effects resolve through. Nil leaves alchemy unavailable.
    public internal(set) var magicEffects: MagicEffectStore?
    /// The plugin ingredient EFID links are relative to.
    var magicItemPlugin = FormIDResolver.loadOrderSpaceName

    let world: any InventoryWorld
    /// Takes `AIPL`, `REMP`, and `CRFT`. The lock coordinator has its own.
    public weak var storyEvents: (any StoryEventReporting)? {
        didSet { locks.storyEvents = storyEvents }
    }

    public init(world: any InventoryWorld, locks: LockCoordinator) {
        self.world = world
        self.locks = locks
    }

    public func wire(
        inventory: InventoryRuntime,
        references: any PapyrusWorldReferenceSource,
        catalog: EquipmentCatalog?,
        pricing: BarterPricing?,
        cellReset: CellResetSettings = .vanilla
    ) {
        let items = WorldItemRuntime(inventory: inventory, references: references)
        self.cellReset = cellReset
        runtime = items
        locks.wire(items: items)
        if let catalog {
            equipment = EquipmentRuntime(inventory: inventory, catalog: catalog)
        }
        if let pricing {
            barterPricing = pricing
        }
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
    public func takeAllFromOpenContainer() -> ItemActionOutcome {
        guard runtime != nil else { return .unavailable }
        guard let session else { return .noContainer }
        do {
            let moved = try session.takeAll()
            reportTaken(moved, from: session)
            return note(.tookAll(moved))
        } catch {
            return note(.failed(action: "Take all", reason: String(describing: error)))
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
