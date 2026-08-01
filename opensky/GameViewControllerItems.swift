// World > HUD & Interaction > Items live bridge (issue #177, roadmap item
// 12.1.3): connects the sidebar section to this session's `WorldItemRuntime`.
//
// Everything here degrades to a stated non-answer rather than to a crash: no
// game data means no item index, which means no inventory runtime, which the
// panel reports as unavailable instead of showing a convincing empty
// inventory. That matters because this section is the milestone's verification
// surface, and it has to stay legible on a machine where the install moved.
//
// The use key routes through here too. `wireWorldItems` subscribes to the
// streamer's interaction fan-out, so pressing the use key on a loose item takes
// it and on a container opens a session — the same operations the buttons run,
// through the same code path, with no second set of rules.

import AppKit

/// State the world-item bridge owns. Stored on `GameViewController` because
/// extensions cannot add stored properties; nothing else writes it.
struct WorldItemBridgeState {
    /// Take/drop/container runtime, built by `wireWorldItems` when the provider
    /// can supply an item index. nil without game data.
    var runtime: WorldItemRuntime?
    /// The container session currently open, if any. At most one: this is a
    /// developer surface, and a second simultaneous chest has no meaning until
    /// menus arrive (#289).
    var session: ContainerSession?
    /// Display name of the open container, captured when the session opened
    /// because the cell holding it may be evicted while it is still open.
    var sessionName: String?
    /// Equip/unequip runtime (issue #178), built beside `runtime` when the
    /// provider can also supply an equipment catalog. nil without game data.
    var equipment: EquipmentRuntime?
    var lastActionText = "No item action yet."
}

extension GameViewController {
    /// Builds the world-item runtime over the provider's item index and
    /// subscribes it to the use key.
    ///
    /// Registered after the audio and Papyrus subscribers so the multicast
    /// order stays: audio first, Papyrus activation second, world items last.
    /// Ordering matters only in that the activation sound should play whether
    /// or not the take succeeds.
    func wireWorldItems(provider: any CellSceneProvider, streamer: CellStreamer) {
        guard let baselines = (provider as? ItemDataProviding)?.inventoryBaselines else {
            return
        }
        let inventory = InventoryRuntime(store: worldState, baselines: baselines)
        let runtime = WorldItemRuntime(inventory: inventory, references: streamer)
        worldItems.runtime = runtime
        if let catalog = (provider as? ItemDataProviding)?.equipmentCatalog {
            worldItems.equipment = EquipmentRuntime(inventory: inventory, catalog: catalog)
        }
        streamer.onInteraction.add { [weak self] event in
            self?.handleItemInteraction(event)
        }
    }

    /// Use-key handling for the two item actions. Every other action —
    /// doors, furniture, harvesting — is somebody else's and passes through.
    private func handleItemInteraction(_ event: InteractionEvent) {
        switch event.target.interaction.action {
        case .take:
            worldItems.lastActionText = takeInteractionTarget()
        case .search:
            worldItems.lastActionText = openInteractionTargetContainer()
        default:
            break
        }
    }

    /// The interaction the crosshair is on, which every action below acts upon.
    private var currentInteraction: PlacedInteraction? {
        hud.interactionTarget?.interaction
    }
}

extension GameViewController: ItemControlProviding {
    var itemControlSnapshot: ItemControlSnapshot {
        guard let runtime = worldItems.runtime else { return .unavailable }
        let interaction = currentInteraction
        let session = worldItems.session
        return ItemControlSnapshot(
            isAvailable: true,
            targetName: interaction?.name,
            targetIsTakeable: interaction?.action == .take,
            targetIsContainer: interaction?.action == .search,
            playerStacks: readout(runtime.inventory.inventory(of: runtime.player).stacks),
            playerWeight: runtime.inventory.carriedWeight(of: runtime.player),
            playerGold: runtime.inventory.goldCount(of: runtime.player),
            containerName: session == nil ? nil : worldItems.sessionName,
            containerStacks: readout(session?.contents ?? []),
            spawnedObjectCount: spawnedObjectCount,
            lastActionText: worldItems.lastActionText,
            playerEquipped: equippedReadout(on: .player),
            nearestActorName: nearestActorHolder().map { name(ofActor: $0) },
            nearestActorEquipped: equippedReadout(on: .nearestActor)
        )
    }

    @discardableResult
    func takeInteractionTarget() -> String {
        guard let runtime = worldItems.runtime else { return Self.noRuntimeText }
        guard let interaction = currentInteraction else {
            return "Nothing under the crosshair to take."
        }
        do {
            let outcome = try runtime.take(interaction)
            worldItems.lastActionText = "Took \(outcome.count) × \(interaction.name)."
        } catch {
            worldItems.lastActionText = "Take failed: \(String(describing: error))"
        }
        return worldItems.lastActionText
    }

    @discardableResult
    func openInteractionTargetContainer() -> String {
        guard let runtime = worldItems.runtime else { return Self.noRuntimeText }
        guard let interaction = currentInteraction else {
            return "Nothing under the crosshair to search."
        }
        // Closing first keeps at most one session live and leaves the previous
        // container's `isOpen` false rather than stuck open forever.
        worldItems.session?.close()
        do {
            let session = try runtime.openContainer(interaction)
            worldItems.session = session
            worldItems.sessionName = interaction.name
            worldItems.lastActionText =
                "Opened \(interaction.name): \(session.totalCount) items."
        } catch {
            worldItems.session = nil
            worldItems.sessionName = nil
            worldItems.lastActionText = "Search failed: \(String(describing: error))"
        }
        return worldItems.lastActionText
    }

    @discardableResult
    func takeAllFromOpenContainer() -> String {
        guard worldItems.runtime != nil else { return Self.noRuntimeText }
        guard let session = worldItems.session else {
            return "No container open."
        }
        do {
            let moved = try session.takeAll()
            let total = moved.reduce(0) { $0 + Int($1.count) }
            worldItems.lastActionText =
                "Took all: \(total) items in \(moved.count) stacks."
        } catch {
            worldItems.lastActionText = "Take all failed: \(String(describing: error))"
        }
        return worldItems.lastActionText
    }

    @discardableResult
    func closeOpenContainer() -> String {
        guard let session = worldItems.session else {
            return "No container open."
        }
        session.close()
        worldItems.session = nil
        worldItems.sessionName = nil
        worldItems.lastActionText = "Closed the container."
        return worldItems.lastActionText
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        guard let runtime = worldItems.runtime else { return Self.noRuntimeText }
        let carried = runtime.inventory.inventory(of: runtime.player).stacks
        guard let target = item ?? carried.first?.item else {
            return "Nothing carried to drop."
        }
        guard let placement = dropPlacement() else {
            return "Drop needs a resident cell; none is loaded."
        }
        do {
            try runtime.drop(target, count: count, at: placement)
            worldItems.lastActionText =
                "Dropped \(count) × \(name(of: target)) in front of the player."
        } catch {
            worldItems.lastActionText = "Drop failed: \(String(describing: error))"
        }
        return worldItems.lastActionText
    }

    // MARK: - Private

    private static let noRuntimeText = "World items unavailable: no game data loaded."

    /// Where a drop lands: a step in front of the camera, a standing height
    /// down, in the cell the player is currently in. Nil when nothing is
    /// resident, because an object needs a cell to exist in.
    private func dropPlacement() -> DropPlacement? {
        guard let renderer, let location = streamer?.currentCellLocation else { return nil }
        return WorldItemRuntime.dropPlacement(
            in: location,
            eye: renderer.freeFlyCamera.position,
            forward: renderer.freeFlyCamera.forward
        )
    }

    /// How many spawned objects the store currently holds, across every cell.
    private var spawnedObjectCount: Int {
        worldState.snapshot().entries.count {
            $0.delta.component(ReferenceSpawnState.self) != nil
        }
    }

    func readout(_ stacks: [InventoryStack]) -> [ItemStackReadout] {
        stacks.map {
            ItemStackReadout(item: $0.item, count: $0.count, name: name(of: $0.item))
        }
    }

    /// FULL name, else editor ID, else the FormID — never empty, so a readout
    /// line always names something even for a form no index describes.
    func name(of item: FormID) -> String {
        guard let definition = worldItems.runtime?.inventory.baselines.items.definition(item) else {
            return item.description
        }
        if case let .inline(value) = definition.name, !value.isEmpty {
            return value
        }
        return definition.editorID ?? item.description
    }
}
