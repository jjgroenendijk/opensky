// World > Inventory Menu > Item: the selected row's card, favourite mark, hotkey, a
// counted drop through the quantity slider, and the turning preview switch.

import AppKit
import OpenSkyMenus

final class InventoryMenuItemSection: PanelSectionViewController {
    weak var provider: (any InventoryMenuControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let favouriteControl = NSButton(title: "Favourite", target: nil, action: nil)
    let hotkeyControl = NSPopUpButton()
    let bindControl = NSButton(title: "Bind hotkey", target: nil, action: nil)
    let useHotkeyControl = NSButton(title: "Use hotkey", target: nil, action: nil)
    let quantityControl = NSButton(title: "Drop…", target: nil, action: nil)
    let fewerControl = NSButton(title: "−1", target: nil, action: nil)
    let moreControl = NSButton(title: "+1", target: nil, action: nil)
    let confirmControl = NSButton(title: "Confirm", target: nil, action: nil)
    let cancelControl = NSButton(title: "Cancel", target: nil, action: nil)
    let previewControl = NSButton(
        checkboxWithTitle: "Turning item preview", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "InventoryMenuItemStatsLabel")

    override var sectionTitle: String {
        "Item"
    }

    override var sectionIdentifier: String {
        "inventoryMenuItem"
    }

    override var isOverridden: Bool {
        provider?.inventoryMenuPreviewEnabled == false
    }

    override func resetToDefaults() {
        provider?.inventoryMenuPreviewEnabled = true
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        hotkeyControl.addItems(withTitles: (1 ... 8).map { "Hotkey \($0)" })
        PanelComponents.configurePopUp(
            hotkeyControl, target: self, action: #selector(noAction),
            identifier: "InventoryMenuHotkeyControl", width: 110
        )
        PanelComponents.configureButtons([
            PanelButtonSpec(
                favouriteControl, #selector(favourite), "InventoryMenuFavouriteControl",
                "Marks or unmarks the row; Space in the menu."
            ),
            PanelButtonSpec(
                bindControl, #selector(bindTapped), "InventoryMenuBindHotkeyControl",
                "Binds the number key to the row."
            ),
            PanelButtonSpec(
                useHotkeyControl, #selector(useHotkey), "InventoryMenuUseHotkeyControl",
                "Does what the number key does in play."
            ),
            PanelButtonSpec(
                quantityControl, #selector(askQuantity), "InventoryMenuQuantityControl",
                "Drops the row; a stack of more than five asks how many, as R does."
            ),
            PanelButtonSpec(
                fewerControl, #selector(fewer), "InventoryMenuFewerControl", "One fewer."
            ),
            PanelButtonSpec(moreControl, #selector(more), "InventoryMenuMoreControl", "One more."),
            PanelButtonSpec(
                confirmControl, #selector(confirm), "InventoryMenuConfirmControl", "Drops them."
            ),
            PanelButtonSpec(
                cancelControl, #selector(cancel), "InventoryMenuCancelControl", "Drops nothing."
            )
        ], target: self)
        PanelComponents.configureCheckbox(
            previewControl, target: self, action: #selector(previewChanged),
            identifier: "InventoryMenuPreviewControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([favouriteControl]),
                PanelComponents.buttonRow([hotkeyControl, bindControl, useHotkeyControl]),
                PanelComponents.buttonRow([quantityControl, fewerControl, moreControl]),
                PanelComponents.buttonRow([confirmControl, cancelControl])
            ]),
            PanelComponents.group([previewControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        previewControl.state = provider?.inventoryMenuPreviewEnabled == false ? .off : .on
        syncEnablement()
    }

    override func refreshReadout() {
        statsLabel.stringValue = provider.map { Self.readout(for: $0.inventoryMenuSnapshot) }
            ?? "Item: unavailable"
        syncEnablement()
    }

    private func syncEnablement() {
        let snapshot = provider?.inventoryMenuSnapshot
        let isOpen = snapshot?.isOpen == true
        let asking = snapshot?.extras.quantity != nil
        for control in [favouriteControl, bindControl, quantityControl] {
            control.isEnabled = isOpen && !asking
        }
        for control in [fewerControl, moreControl, confirmControl, cancelControl] {
            control.isEnabled = asking
        }
        useHotkeyControl.isEnabled = provider != nil
        previewControl.isEnabled = provider != nil
    }

    nonisolated static func readout(for snapshot: InventoryMenuControlSnapshot) -> String {
        let extras = snapshot.extras
        var lines = extras.itemCard.isEmpty ? ["Card: no row selected"] : extras.itemCard
        if let quantity = extras.quantity {
            lines.append(quantity)
        }
        lines.append(extras.hotkeys.isEmpty
            ? "Hotkeys: none" : "Hotkeys: " + extras.hotkeys.joined(separator: ", "))
        let preview = extras.previewEnabled ? extras.previewLine ?? "menu closed" : "off"
        lines.append("Preview: \(preview)")
        return lines.joined(separator: "\n")
    }

    private var slot: Int {
        hotkeyControl.indexOfSelectedItem + 1
    }

    @objc private func noAction() {}

    @objc private func favourite() {
        provider?.toggleInventoryMenuFavourite()
        finishInteraction()
    }

    @objc private func bindTapped() {
        provider?.bindInventoryMenuHotkey(slot)
        finishInteraction()
    }

    @objc private func useHotkey() {
        provider?.useInventoryHotkey(slot)
        finishInteraction()
    }

    @objc private func askQuantity() {
        provider?.sendInventoryMenuInput(.button(.xButton))
        finishInteraction()
    }

    @objc private func fewer() {
        provider?.sendInventoryMenuInput(.move(.left))
        finishInteraction()
    }

    @objc private func more() {
        provider?.sendInventoryMenuInput(.move(.right))
        finishInteraction()
    }

    @objc private func confirm() {
        provider?.sendInventoryMenuInput(.button(.accept))
        finishInteraction()
    }

    @objc private func cancel() {
        provider?.sendInventoryMenuInput(.button(.cancel))
        finishInteraction()
    }

    @objc private func previewChanged() {
        provider?.inventoryMenuPreviewEnabled = previewControl.state == .on
        finishInteraction()
    }
}
