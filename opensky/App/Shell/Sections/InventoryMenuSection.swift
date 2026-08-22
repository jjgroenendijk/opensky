// World > Inventory Menu > Menu: opens the engine's menu stack on the player's
// inventory and drives the row list (M12.2.2, issue #289). Every button routes
// the same `MenuInputEvent` the keyboard produces in menu mode, so the panel
// cannot diverge from live input.

import AppKit

final class InventoryMenuSection: PanelSectionViewController {
    weak var provider: (any InventoryMenuControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let openControl = NSButton(title: "Open", target: nil, action: nil)
    let closeControl = NSButton(title: "Close", target: nil, action: nil)
    let upControl = NSButton(title: "Up", target: nil, action: nil)
    let downControl = NSButton(title: "Down", target: nil, action: nil)
    let previousCategoryControl = NSButton(title: "Prev category", target: nil, action: nil)
    let nextCategoryControl = NSButton(title: "Next category", target: nil, action: nil)
    let equipControl = NSButton(title: "Equip / unequip", target: nil, action: nil)
    let dropControl = NSButton(title: "Drop", target: nil, action: nil)
    let consumeControl = NSButton(title: "Consume", target: nil, action: nil)
    let movieControl = NSButton(
        checkboxWithTitle: "Vanilla menu movie", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "InventoryMenuStatsLabel")

    var statsReadout: String {
        statsLabel.stringValue
    }

    override var sectionTitle: String {
        "Menu"
    }

    override var sectionIdentifier: String {
        "inventoryMenu"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// An open menu pauses world sim, and the movie takes the SWF layer from
    /// the gameplay HUD. Both are states a user must be able to see and clear
    /// from the sidebar without hunting for the control that set them.
    static func isOverridden(provider: (any InventoryMenuControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.inventoryMenuIsOpen || provider.inventoryMenuMovieEnabled
    }

    static func resetToDefaults(provider: (any InventoryMenuControlProviding)?) {
        guard let provider else { return }
        provider.closeInventoryMenu()
        provider.inventoryMenuMovieEnabled = false
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([openControl, closeControl]),
                PanelComponents.buttonRow([upControl, downControl]),
                PanelComponents.buttonRow([previousCategoryControl, nextCategoryControl]),
                PanelComponents.buttonRow([equipControl, dropControl, consumeControl])
            ]),
            PanelComponents.group([movieControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        movieControl.state = provider?.inventoryMenuMovieEnabled == true ? .on : .off
        syncEnablement()
    }

    override func refreshReadout() {
        guard let snapshot = provider?.inventoryMenuSnapshot else {
            statsLabel.stringValue = "Inventory menu: unavailable"
            syncEnablement()
            return
        }
        statsLabel.stringValue = Self.readout(for: snapshot)
        // The menu also opens and closes from live keyboard input, so button
        // enablement has to follow the readout tick, not just control actions.
        syncEnablement()
    }

    private func syncEnablement() {
        let isOpen = provider?.inventoryMenuIsOpen == true
        openControl.isEnabled = provider != nil && !isOpen
        let whileOpen: [NSControl] = [
            closeControl, upControl, downControl, previousCategoryControl,
            nextCategoryControl, equipControl, dropControl, consumeControl
        ]
        for control in whileOpen {
            control.isEnabled = isOpen
        }
        movieControl.isEnabled = provider != nil
    }

    /// One row line. Pure and static so the movie bridge, the readout, and the
    /// tests all format a row the same way.
    nonisolated static func line(for entry: InventoryMenuEntry) -> String {
        let count = entry.count == 1 ? "" : " ×\(entry.count)"
        let equipped = entry.isEquipped ? " [equipped]" : ""
        // "Stolen items in your inventory will be marked with the word
        // 'Stolen'" (<https://en.uesp.net/wiki/Skyrim:Crime>). The count is
        // spelled out when only some of the row is hot, because the row is one
        // item and the flag is per copy (issue #504).
        let stolen = switch entry.stolenCount {
        case 0: ""
        case entry.count: " [stolen]"
        default: " [\(entry.stolenCount) stolen]"
        }
        let weight = String(format: "%.1f", entry.weight)
        return "\(entry.name)\(count)\(equipped)\(stolen) · \(weight) wt · \(entry.value) gold"
    }

    /// Pure so the readout is unit-testable without AppKit state.
    nonisolated static func readout(for snapshot: InventoryMenuControlSnapshot) -> String {
        guard snapshot.isOpen else {
            return "Inventory menu: closed · world sim running"
        }
        let sim = snapshot.worldSimPaused ? "paused" : "running"
        let stack = snapshot.openMenus.isEmpty ? "none" : snapshot.openMenus.joined(separator: ", ")
        let weight = String(format: "%.1f", snapshot.carriedWeight)
        let action = snapshot.lastActionText.map { "\nLast action: \($0)" } ?? ""
        return """
        Inventory menu: open · world sim \(sim)
        Stack: \(stack)
        \(categoryLine(for: snapshot))
        \(rows(for: snapshot))
        Carrying \(weight) · \(snapshot.gold) gold\(action)
        \(enchantmentDetail(for: snapshot))
        \(movieReadout(for: snapshot))
        """
    }

    /// The equipped-item detail every enchanted piece adds: what it grants and
    /// how much charge is left (issue #472). One line saying so when nothing
    /// equipped is enchanted, rather than a silently missing block.
    nonisolated static func enchantmentDetail(
        for snapshot: InventoryMenuControlSnapshot
    ) -> String {
        guard !snapshot.enchantmentLines.isEmpty else {
            return "Enchanted equipment: none"
        }
        return (["Enchanted equipment:"] + snapshot.enchantmentLines.map { "  \($0)" })
            .joined(separator: "\n")
    }

    nonisolated static func categoryLine(for snapshot: InventoryMenuControlSnapshot) -> String {
        guard !snapshot.categoryLabels.isEmpty else {
            return "Categories: none"
        }
        let tabs = snapshot.categoryLabels.enumerated().map { index, label in
            index == snapshot.selectedCategoryIndex ? "[\(label)]" : label
        }.joined(separator: " ")
        return "Categories: \(tabs)"
    }

    nonisolated static func rows(for snapshot: InventoryMenuControlSnapshot) -> String {
        guard !snapshot.entryLines.isEmpty else {
            return "  (no items in this category)"
        }
        return snapshot.entryLines.enumerated().map { index, line in
            (index == snapshot.selectedIndex ? "> " : "  ") + line
        }.joined(separator: "\n")
    }

    nonisolated static func movieReadout(for snapshot: InventoryMenuControlSnapshot) -> String {
        guard snapshot.movieEnabled else {
            return "Movie: off (engine-drawn row list)"
        }
        if let error = snapshot.movieError {
            return "Movie: failed · \(error)"
        }
        guard snapshot.movieLoaded else {
            return "Movie: not loaded"
        }
        // Print the rows the movie built for itself so the verification surface
        // proves the engine's list actually crossed the bridge.
        let rows = snapshot.movieEntryTitles.isEmpty
            ? "no rows"
            : snapshot.movieEntryTitles.joined(separator: ", ")
        let tabs = snapshot.movieCategoryTitles.isEmpty
            ? "no categories"
            : snapshot.movieCategoryTitles.joined(separator: ", ")
        return "Movie: \(InventoryMenuMovieBridge.moviePath) · "
            + "\(snapshot.movieDrawStats.drawCalls) draws · "
            + "\(snapshot.movieFaults) faults · "
            + "\(snapshot.movieMissingNames) missing names · "
            + "\(snapshot.movieUnhandledInvokes) unhandled invokes"
            + "\nMovie categories: \(tabs)"
            + "\nMovie rows: \(rows)"
    }

    private func configureControls() {
        configure(openControl, action: #selector(openTapped), id: "InventoryMenuOpenControl")
        configure(closeControl, action: #selector(closeTapped), id: "InventoryMenuCloseControl")
        configure(upControl, action: #selector(upTapped), id: "InventoryMenuUpControl")
        configure(downControl, action: #selector(downTapped), id: "InventoryMenuDownControl")
        configure(
            previousCategoryControl, action: #selector(previousCategoryTapped),
            id: "InventoryMenuPreviousCategoryControl"
        )
        configure(
            nextCategoryControl, action: #selector(nextCategoryTapped),
            id: "InventoryMenuNextCategoryControl"
        )
        configure(equipControl, action: #selector(equipTapped), id: "InventoryMenuEquipControl")
        configure(dropControl, action: #selector(dropTapped), id: "InventoryMenuDropControl")
        configure(
            consumeControl, action: #selector(consumeTapped), id: "InventoryMenuConsumeControl"
        )
        PanelComponents.configureCheckbox(
            movieControl, target: self, action: #selector(movieChanged),
            identifier: "InventoryMenuMovieControl"
        )
    }

    private func configure(_ control: NSButton, action: Selector, id: String) {
        PanelComponents.configureButton(
            control, target: self, action: action, identifier: id
        )
    }

    @objc private func openTapped() {
        provider?.openInventoryMenu()
        finishInteraction()
    }

    @objc private func closeTapped() {
        provider?.closeInventoryMenu()
        finishInteraction()
    }

    @objc private func upTapped() {
        provider?.sendInventoryMenuInput(.move(.up))
        finishInteraction()
    }

    @objc private func downTapped() {
        provider?.sendInventoryMenuInput(.move(.down))
        finishInteraction()
    }

    @objc private func previousCategoryTapped() {
        provider?.sendInventoryMenuInput(.move(.left))
        finishInteraction()
    }

    @objc private func nextCategoryTapped() {
        provider?.sendInventoryMenuInput(.move(.right))
        finishInteraction()
    }

    @objc private func equipTapped() {
        provider?.activateInventoryMenuSelection()
        finishInteraction()
    }

    @objc private func dropTapped() {
        provider?.dropInventoryMenuSelection()
        finishInteraction()
    }

    @objc private func consumeTapped() {
        provider?.consumeInventoryMenuSelection()
        finishInteraction()
    }

    @objc private func movieChanged() {
        provider?.inventoryMenuMovieEnabled = movieControl.state == .on
        finishInteraction()
    }
}
