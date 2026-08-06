// The engine-side two-pane transfer list (M12.2.3, issue #179): what the
// container and barter menus show, which side the player is looking at, and
// what activating a row would do.
//
// Both vanilla movies present one item list at a time and swap which owner it
// belongs to, so this is two `InventoryMenuModel` panes and a side, not a new
// row type. Reusing #289's list is what keeps the inventory, container and
// barter menus agreeing about what an item row is, how rows sort, and how gold
// is split out of them.
//
// Device-free, AppKit-free and renderer-free, so it builds into `openskycli` and
// is unit-testable against a synthetic `ItemDefinitionStore`.
//
// Documented in docs/engine/barter.md.

import Foundation

/// The transfer list one container or merchant session presents.
nonisolated struct ContainerMenuModel: Equatable, Sendable {
    /// Which owner's items the single item list is showing.
    enum Side: String, Equatable, Sendable {
        /// The container or merchant. Vanilla opens on this side, because the
        /// point of opening a chest is to see what is in it.
        case container
        case player
    }

    /// What activating a row means.
    enum Mode: String, Equatable, Sendable {
        /// `containermenu.swf`: rows move for free.
        case container
        /// `bartermenu.swf`: rows move for gold, priced by `pricing`.
        case barter
    }

    let mode: Mode
    /// The container's or merchant's own list, including its gold.
    var container: InventoryMenuModel
    var player: InventoryMenuModel
    private(set) var side: Side
    /// The price factors in force. Present in container mode too, where nothing
    /// consults it, so the two modes differ by one flag rather than by shape.
    let pricing: BarterPricing
    /// How the container names itself in the readout, from its base record.
    let containerName: String

    static let empty = ContainerMenuModel(
        mode: .container,
        container: .empty,
        player: .empty,
        pricing: .vanilla,
        containerName: "none"
    )

    init(
        mode: Mode,
        container: InventoryMenuModel,
        player: InventoryMenuModel,
        pricing: BarterPricing,
        containerName: String,
        side: Side = .container
    ) {
        self.mode = mode
        self.container = container
        self.player = player
        self.pricing = pricing
        self.containerName = containerName
        self.side = side
    }

    // MARK: - Reading

    /// The pane the item list is showing.
    var active: InventoryMenuModel {
        get { side == .container ? container : player }
        set {
            if side == .container {
                container = newValue
            } else {
                player = newValue
            }
        }
    }

    var selectedEntry: InventoryMenuEntry? {
        active.selectedEntry
    }

    /// The merchant's purse, which is an ordinary gold stack in the container's
    /// own inventory rather than a separate field.
    var containerGold: Int32 {
        container.gold
    }

    var playerGold: Int32 {
        player.gold
    }

    /// What one of `entry` costs on the side it is displayed on: the buy price
    /// for the merchant's stock, the sell price for the player's. Nil in
    /// container mode, where nothing is priced.
    func price(for entry: InventoryMenuEntry) -> Int32? {
        guard mode == .barter else { return nil }
        return side == .container
            ? pricing.buyPrice(value: entry.value)
            : pricing.sellPrice(value: entry.value)
    }

    /// What activating the selected row would do, as the vanilla movies label
    /// it: `$Take` / `$Store` for a container, `$Buy` / `$Sell` for a merchant.
    var transferLabel: String {
        switch (mode, side) {
        case (.container, .container): "Take"
        case (.container, .player): "Store"
        case (.barter, .container): "Buy"
        case (.barter, .player): "Sell"
        }
    }

    /// Whether the price of the selected row can actually be paid, so the menu
    /// can disable a row rather than offer a transaction that will be refused.
    /// True in container mode, where nothing is paid for.
    var canAffordSelection: Bool {
        guard mode == .barter, let entry = selectedEntry, let price = price(for: entry) else {
            return true
        }
        return side == .container ? playerGold >= price : containerGold >= price
    }

    // MARK: - Navigation

    /// Swaps which owner the item list shows and returns the row selection to
    /// the top of the new side, for the same reason a category change does: the
    /// other side's rows are a different list.
    mutating func switchSide() {
        side = side == .container ? .player : .container
        active.select(0)
    }

    mutating func select(side newSide: Side) {
        guard newSide != side else { return }
        switchSide()
    }

    mutating func moveSelection(by offset: Int) {
        active.moveSelection(by: offset)
    }

    mutating func moveCategory(by offset: Int) {
        active.moveCategory(by: offset)
    }

    mutating func select(_ index: Int) {
        active.select(index)
    }

    mutating func selectCategory(_ index: Int) {
        active.selectCategory(index)
    }

    /// Carries `previous`'s side and both panes' selections onto a freshly
    /// rebuilt model.
    ///
    /// Every transfer rebuilds both panes from the store, and without this a
    /// player who takes the third item would find the cursor back at the top.
    /// A selection that no longer exists — the row that just moved out — is
    /// dropped by `select`'s own bounds check rather than clamped here.
    mutating func restore(from previous: ContainerMenuModel) {
        side = previous.side
        container.selectCategory(previous.container.selectedCategoryIndex)
        container.select(previous.container.selectedIndex)
        player.selectCategory(previous.player.selectedCategoryIndex)
        player.select(previous.player.selectedIndex)
    }
}

@MainActor
extension ContainerMenuModel {
    /// The live two-pane list for one container, read through the runtime that
    /// owns both stored inventories and the definitions behind them.
    ///
    /// Both panes are built by #289's builder, so the container's rows sort,
    /// name themselves and split gold out exactly as the player's do.
    static func build(
        container: InventoryHolder,
        containerName: String,
        mode: Mode,
        pricing: BarterPricing,
        runtime: InventoryRuntime
    ) -> ContainerMenuModel {
        ContainerMenuModel(
            mode: mode,
            container: InventoryMenuModel.build(holder: container, runtime: runtime),
            player: InventoryMenuModel.build(holder: .player, runtime: runtime),
            pricing: pricing,
            containerName: containerName
        )
    }
}
