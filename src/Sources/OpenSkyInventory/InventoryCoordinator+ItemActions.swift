// The item actions of the use key and the Items readout: take, search, drop, and close.

import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
public import OpenSkyWorldInterface

extension InventoryCoordinator.ItemActions {
    /// The use key: take a loose item, search a container, harvest a plant, or
    /// use a crafting station. Other actions belong to other domains and pass through.
    public func handleInteraction(_ action: InteractionAction) -> [InventoryCommand] {
        switch action {
        case .take:
            coordinator.note(takeInteractionTarget())
        case .search:
            coordinator.note(openInteractionTargetContainer())
        case .harvest:
            return coordinator.craftingBench.harvestInteractionTarget().commands
        case .use:
            if
                let station = coordinator.world.crosshairInteraction
                    .flatMap(CraftingActivationEvent.init)
            {
                coordinator.craftingBench.openCraftingSession(station)
            }
        default:
            break
        }
        return []
    }

    @discardableResult
    public func takeInteractionTarget() -> ItemActionOutcome {
        guard coordinator.runtime != nil else { return .unavailable }
        guard let interaction = coordinator.world.crosshairInteraction else {
            return .nothingUnderCrosshair(verb: "take")
        }
        return take(interaction)
    }

    /// Takes the item behind `interaction`, such as a book read where it lies.
    @discardableResult
    public func take(_ interaction: PlacedInteraction) -> ItemActionOutcome {
        guard let runtime = coordinator.runtime else { return .unavailable }
        do {
            let outcome = try runtime.take(interaction)
            coordinator.storyEvents?.reportStoryEvent(.addItem(
                outcome.item, from: nil, owner: nil, how: outcome.stolen ? .steal : .pickUp
            ))
            return coordinator.note(.took(count: outcome.count, item: interaction.name))
        } catch {
            return coordinator.note(.failed(action: "Take", reason: String(describing: error)))
        }
    }

    @discardableResult
    public func openInteractionTargetContainer() -> ItemActionOutcome {
        guard let runtime = coordinator.runtime else { return .unavailable }
        guard let interaction = coordinator.world.crosshairInteraction else {
            return .nothingUnderCrosshair(verb: "search")
        }
        // Closing first keeps one session live and leaves the previous
        // container's `isOpen` false.
        coordinator.session?.close()
        do {
            let opened = try ContainerSession.open(interaction, in: runtime)
            coordinator.session = opened
            coordinator.sessionName = interaction.name
            return coordinator.note(.opened(container: interaction.name, items: opened.totalCount))
        } catch {
            coordinator.session = nil
            coordinator.sessionName = nil
            return coordinator.note(.failed(action: "Search", reason: String(describing: error)))
        }
    }

    @discardableResult
    func closeOpenContainer() -> ItemActionOutcome {
        guard let session = coordinator.session else { return .noContainer }
        session.close()
        coordinator.session = nil
        coordinator.sessionName = nil
        return coordinator.note(.closed)
    }

    /// Drops `item`, or the first carried stack when `item` is nil.
    @discardableResult
    public func dropPlayerItem(_ item: FormID?, count: Int32) -> ItemActionOutcome {
        guard let runtime = coordinator.runtime else { return .unavailable }
        let carried = runtime.inventory.inventory(of: runtime.player).stacks
        guard let target = item ?? carried.first?.item else { return .nothingToDrop }
        guard let placement = coordinator.world.dropPlacement() else { return .noDropCell }
        do {
            try runtime.drop(target, count: count, at: placement)
            coordinator.storyEvents?.reportStoryEvent(.removeItem(
                target, reference: nil, owner: nil, how: .dropped
            ))
            return coordinator.note(.dropped(count: count, item: coordinator.name(of: target)))
        } catch {
            return coordinator.note(.failed(action: "Drop", reason: String(describing: error)))
        }
    }

    /// A dead actor's drawn weapon falls to `placement`, out of its inventory.
    /// - Returns: the item dropped, or nil when the actor holds no drawn weapon.
    @discardableResult
    public func dropWeapon(of holder: InventoryHolder, at placement: DropPlacement) -> FormID? {
        guard
            let runtime = coordinator.runtime, let equipment = coordinator.equipment,
            let weapon = equipment.equipped(on: holder).first(where: { item in
                equipment.catalog.item(item)?.animationType != nil
                    && equipment.catalog.item(item)?.occupancy.hands.contains(.rightHand) == true
            }),
            attempt({ try runtime.drop(weapon, count: 1, from: holder, at: placement) }) != nil
        else { return nil }
        coordinator.storyEvents?.reportStoryEvent(.removeItem(
            weapon, reference: nil, owner: nil, how: .dropped
        ))
        return weapon
    }
}
