// The inventory menu's favourites, hotkeys, quantity slider, item card, and turning
// preview. R drops and Space marks a favourite, because the menu has no F binding.
// See docs/engine/inventory-menu.md.

import Foundation
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyRendering

extension InventoryMenuController {
    // MARK: - Favourites and hotkeys

    func toggleFavouriteSelection() {
        perform { game.inventory.toggleFavourite($0.item).text }
    }

    /// A number key in play: equips or unequips the bound item, or uses a potion,
    /// food, ingredient, or poison, as activating its row would.
    func useHotkey(_ slot: Int) {
        switch game.inventory.hotkeyItem(slot) {
        case let .failure(outcome):
            lastActionText = outcome.text
        case let .success(item):
            lastActionText = use(item)
        }
        game.hud.showNotification(lastActionText ?? "")
        if isOpen {
            refreshModel()
        }
    }

    func use(_ item: FormID) -> String {
        let inventory = game.inventory
        switch inventory.use(of: item) {
        case .applyPoison: return inventory.applyPoison(item).text
        case .consume: return game.magic.consumeMagicItem(item).text
        case .unequip: return game.inventoryWorld.run(inventory.unequipItem(item, on: .player)).text
        case .equip: return game.inventoryWorld.run(inventory.equipItem(item, on: .player)).text
        }
    }

    // MARK: - Quantity

    /// R, or the movie's drop: a stack of more than five asks how many first.
    func requestDrop() {
        guard let entry = model.selectedEntry else {
            lastActionText = "No row selected."
            return
        }
        guard
            let prompt = InventoryQuantityPrompt.asking(
                item: entry.item, name: entry.name, count: entry.count
            )
        else {
            dropSelection()
            return
        }
        model.quantity = prompt
        lastActionText = prompt.text
    }

    /// Left and right move by one, up and down by ten; accept drops, cancel keeps all.
    func routeQuantity(_ event: MenuInputEvent) {
        switch event {
        case .button(.accept), .button(.xButton):
            let count = model.quantity?.value ?? 1
            model.quantity = nil
            dropSelection(count: count)
        case .button(.cancel):
            model.quantity = nil
            lastActionText = "Dropped nothing."
        case let .move(direction):
            let step: Int32 = switch direction {
            case .left: -1
            case .right: 1
            case .down: -10
            case .up: 10
            }
            model.quantity?.adjust(by: step)
            lastActionText = model.quantity?.text
        case .button(.yButton), .pointer, .release:
            return
        }
    }

    // MARK: - Preview

    /// Each frame while the menu is open: turns the selected row's model.
    func tick(now: Double) {
        guard isOpen, previewEnabled, let renderer = game.renderer else { return }
        let path = model.selectedEntry.flatMap {
            game.inventory.runtime?.inventory.baselines.items.definition($0.item)?.modelPath
        }
        preview.show(path)
        preview.tick(now: now)
        if previewSource == nil, let files = game.worldData?.scriptFileSystem {
            previewSource = InventoryItemPreviewSource(fileSystem: files)
        }
        let scene = previewSource?.scene(for: preview, device: renderer.device)
        guard scene != nil || previewShown else { return }
        previewShown = scene != nil
        renderer.setMenuScene(scene)
    }

    func hidePreview() {
        preview.show(nil)
        guard previewShown else { return }
        previewShown = false
        game.renderer?.setMenuScene(nil)
    }

    // MARK: - Readout

    var extrasSnapshot: InventoryMenuExtras {
        let favourites = game.inventory.playerFavourites
        return InventoryMenuExtras(
            itemCard: model.selectedEntry.flatMap { game.inventory.itemCard(for: $0.item) }?
                .lines ?? [],
            quantity: model.quantity?.text,
            hotkeys: favourites.hotkeys.sorted { $0.key < $1.key }.map {
                "\($0.key): \(game.inventory.name(of: $0.value))"
            },
            previewEnabled: previewEnabled,
            previewLine: previewLine
        )
    }

    private var previewLine: String? {
        guard let path = preview.modelPath else {
            return isOpen ? "no model for this row" : nil
        }
        if let failure = previewSource?.failures[path] {
            return "\(path): \(failure)"
        }
        let degrees = Int((preview.yaw * 180 / .pi).rounded())
        return previewShown ? "\(path), turned \(degrees)°" : "\(path), loading"
    }
}
