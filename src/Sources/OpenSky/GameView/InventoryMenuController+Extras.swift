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
import OpenSkyMenusInterface
import OpenSkyRendering
import OpenSkySessionInterface

extension InventoryMenuController {
    // MARK: - Favourites and hotkeys

    func toggleFavouriteSelection() {
        perform {
            itemActions.refusal(.favourite, of: $0.item)
                ?? game.inventory.favouriteItems.toggleFavourite($0.item).text
        }
    }

    /// A number key in play: equips or unequips the bound item, or uses a potion,
    /// food, ingredient, or poison, as activating its row would.
    func useHotkey(_ slot: Int) {
        switch game.inventory.favouriteItems.hotkeyItem(slot) {
        case let .failure(outcome):
            lastActionText = outcome.text
        case let .success(item):
            // A refusal shows its own notice.
            let request = itemActions.request(
                for: game.inventory.consumables.use(of: item),
                item: item
            )
            if let refused = itemActions.refusal(request, of: item) {
                lastActionText = refused
                return
            }
            lastActionText = itemActions.use(item)
        }
        game.hud.showNotification(lastActionText ?? "")
        if isOpen {
            refreshModel()
        }
    }

    // MARK: - Quantity

    /// R: a stack of more than five asks how many first. The movie's `DropItem`
    /// opens its own quantity slider; without a movie the engine asks.
    func requestDrop() {
        guard let entry = model.selectedEntry else {
            lastActionText = "No row selected."
            return
        }
        if requestMovieDrop() {
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

    /// True when the movie took the drop: it dropped one or opened its slider.
    private func requestMovieDrop() -> Bool {
        movieAnsweredDrop = false
        var called = false
        movie.publish { called = InventoryMenuMovieBridge.requestDrop(runtime: $0) }
        return called && movieAnsweredDrop
    }

    /// Keys for the movie's slider: left and right move it, accept drops, cancel keeps all.
    func routeMovieQuantity(_ event: MenuInputEvent) {
        guard let renderer = movie.loadedRenderer else {
            movieQuantityOpen = false
            return
        }
        do {
            try ItemCardSubMenuBridge.send(event, renderer: renderer)
        } catch {
            movie.record(error)
            movieQuantityOpen = false
        }
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
        case .button(.yButton), .button(.leftEquip), .pointer, .release, .activate:
            return
        }
    }

    // MARK: - Preview

    /// Each frame while the menu is open: steps the movie, so its slides and fades
    /// run, and turns the selected row's model.
    func tick(now: Double) {
        guard isOpen else { return }
        movie.advance(now: now)
        guard previewEnabled, let renderer = game.renderer else { return }
        // A live movie decides through `UpdateItem3D`; without one the row shows.
        let shown = movie.loadedRenderer == nil || movieShowsItem3D
        let path = InventoryPreviewReads.modelPath(of: model.selectedEntry, game: game)
        preview.show(shown ? path : nil)
        preview.tick(now: now)
        if previewSource == nil {
            previewSource = InventoryPreviewReads.source(game: game)
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
}

/// The world reads behind the inventory menu's item preview.
@MainActor
enum InventoryPreviewReads {
    static func modelPath(of entry: InventoryMenuEntry?, game: any InventoryMenuHost) -> String? {
        entry.flatMap {
            game.inventory.runtime?.inventory.baselines.items.definition($0.item)?.modelPath
        }
    }

    static func source(game: any InventoryMenuHost) -> InventoryItemPreviewSource? {
        game.worldData?.scriptFileSystem.map { InventoryItemPreviewSource(fileSystem: $0) }
    }
}
