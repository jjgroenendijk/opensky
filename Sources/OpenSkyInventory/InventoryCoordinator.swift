// The shell of the inventory domain: owns the world-item and equipment
// runtimes, the open container session, and the panel readout lines. The
// rules live in `InventoryCore`. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

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
    public private(set) var lastActionText = "No item action yet."
    /// Kept apart from `lastActionText`, so a grant does not overwrite the
    /// take and drop readout on the other panel.
    public private(set) var lastGrantText = "No grant yet."
    /// The NPC by default: an equip is only visible on a rendered actor.
    public var inspectionTarget = EquipmentTargetSelector.nearestActor
    /// Nil without a FACT and FLST index.
    public var vendors: VendorCoordinator?
    /// Lock state, keys, and lockpicking, over the same world-item runtime.
    public let locks = LockCoordinator()
    /// Nil without recipe data.
    public internal(set) var craftingCatalog: CraftingCatalog?
    /// At most one station is in use at a time.
    public internal(set) var crafting: CraftingSession?
    public internal(set) var lastCraftText = "No crafting action yet."
    weak var recipeConditions: (any RecipeConditionChecking)?
    weak var skillUses: (any SkillUseReporting)?

    weak var world: (any InventoryWorld)?

    public init() {}

    public func attach(world: any InventoryWorld) {
        self.world = world
    }

    public func wire(
        inventory: InventoryRuntime,
        references: any PapyrusWorldReferenceSource,
        catalog: EquipmentCatalog?,
        pricing: BarterPricing?
    ) {
        let items = WorldItemRuntime(inventory: inventory, references: references)
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
    public func handleInteraction(_ action: InteractionAction) {
        switch action {
        case .take:
            lastActionText = takeInteractionTarget()
        case .search:
            lastActionText = openInteractionTargetContainer()
        case .harvest:
            lastActionText = harvestInteractionTarget()
        case .use:
            if let station = world?.crosshairInteraction.flatMap(CraftingActivationEvent.init) {
                openCraftingSession(station)
            }
        default:
            break
        }
    }

    // MARK: - Item actions

    @discardableResult
    public func takeInteractionTarget() -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        guard let interaction = world?.crosshairInteraction else {
            return "Nothing under the crosshair to take."
        }
        do {
            let outcome = try runtime.take(interaction)
            return note("Took \(outcome.count) × \(interaction.name).")
        } catch {
            return note("Take failed: \(String(describing: error))")
        }
    }

    @discardableResult
    public func openInteractionTargetContainer() -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        guard let interaction = world?.crosshairInteraction else {
            return "Nothing under the crosshair to search."
        }
        // Closing first keeps one session live and leaves the previous
        // container's `isOpen` false.
        session?.close()
        do {
            let opened = try runtime.openContainer(interaction)
            session = opened
            sessionName = interaction.name
            return note("Opened \(interaction.name): \(opened.totalCount) items.")
        } catch {
            session = nil
            sessionName = nil
            return note("Search failed: \(String(describing: error))")
        }
    }

    @discardableResult
    public func takeAllFromOpenContainer() -> String {
        guard runtime != nil else { return InventoryCore.noRuntimeText }
        guard let session else { return InventoryCore.noContainerText }
        do {
            return try note(InventoryCore.takeAllSentence(session.takeAll()))
        } catch {
            return note("Take all failed: \(String(describing: error))")
        }
    }

    @discardableResult
    public func closeOpenContainer() -> String {
        guard let session else { return InventoryCore.noContainerText }
        session.close()
        self.session = nil
        sessionName = nil
        return note("Closed the container.")
    }

    /// Drops `item`, or the first carried stack when `item` is nil.
    @discardableResult
    public func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        let carried = runtime.inventory.inventory(of: runtime.player).stacks
        guard let target = item ?? carried.first?.item else {
            return "Nothing carried to drop."
        }
        guard let placement = world?.dropPlacement() else {
            return "Drop needs a resident cell; none is loaded."
        }
        do {
            try runtime.drop(target, count: count, at: placement)
            return note("Dropped \(count) × \(name(of: target)) in front of the player.")
        } catch {
            return note("Drop failed: \(String(describing: error))")
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
                detail: runtime?.inventory.baselines.items.familyDetail($0.item)
            )
        }
    }

    func note(_ text: String) -> String {
        lastActionText = text
        return text
    }

    func noteGrant(_ text: String) -> String {
        lastGrantText = text
        return text
    }
}
