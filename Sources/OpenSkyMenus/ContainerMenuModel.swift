// The engine-side two-pane transfer list: what the container and barter menus
// show, which side the player looks at, and what activating a row does. Both
// vanilla movies show one owner's list at a time, so this is two
// `InventoryMenuModel` panes and a side. Sharing the inventory list keeps row
// sorting and gold handling the same in all three menus (docs/engine/barter.md).

import Foundation
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The transfer list one container or merchant session presents.
nonisolated public struct ContainerMenuModel: Equatable, Sendable {
    /// Which owner's items the single item list is showing.
    public enum Side: String, Equatable, Sendable {
        /// The container or merchant. Vanilla opens on this side, because the
        /// point of opening a chest is to see what is in it.
        case container
        case player
    }

    /// What activating a row means.
    public enum Mode: String, Equatable, Sendable {
        /// `containermenu.swf`: rows move for free.
        case container
        /// `bartermenu.swf`: rows move for gold, priced by `pricing`.
        case barter
    }

    public let mode: Mode
    /// The container's or merchant's own list, including its gold.
    public var container: InventoryMenuModel
    public var player: InventoryMenuModel
    public private(set) var side: Side
    /// The price factors in force. Present in container mode too, where nothing
    /// consults it, so the two modes differ by one flag rather than by shape.
    public let pricing: BarterPricing
    /// How the container names itself in the readout, from its base record.
    public let containerName: String

    public static let empty = ContainerMenuModel(
        mode: .container,
        container: .empty,
        player: .empty,
        pricing: .vanilla,
        containerName: "none"
    )

    public init(
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
    public var active: InventoryMenuModel {
        get { side == .container ? container : player }
        set {
            if side == .container {
                container = newValue
            } else {
                player = newValue
            }
        }
    }

    public var selectedEntry: InventoryMenuEntry? {
        active.selectedEntry
    }

    /// The merchant's purse, which is an ordinary gold stack in the container's
    /// own inventory rather than a separate field.
    public var containerGold: Int32 {
        container.gold
    }

    public var playerGold: Int32 {
        player.gold
    }

    /// What one of `entry` costs on the side it is displayed on: the buy price
    /// for the merchant's stock, the sell price for the player's. Nil in
    /// container mode, where nothing is priced.
    public func price(for entry: InventoryMenuEntry) -> Int32? {
        guard mode == .barter else { return nil }
        return side == .container
            ? pricing.buyPrice(value: entry.value)
            : pricing.sellPrice(value: entry.value)
    }

    /// What activating the selected row would do, as the vanilla movies label
    /// it: `$Take` / `$Store` for a container, `$Buy` / `$Sell` for a merchant.
    public var transferLabel: String {
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
    public var canAffordSelection: Bool {
        guard mode == .barter, let entry = selectedEntry, let price = price(for: entry) else {
            return true
        }
        return side == .container ? playerGold >= price : containerGold >= price
    }

    // MARK: - Navigation

    /// Swaps which owner the item list shows and returns the row selection to
    /// the top of the new side, for the same reason a category change does: the
    /// other side's rows are a different list.
    public mutating func switchSide() {
        side = side == .container ? .player : .container
        active.select(0)
    }

    public mutating func select(side newSide: Side) {
        guard newSide != side else { return }
        switchSide()
    }

    public mutating func moveSelection(by offset: Int) {
        active.moveSelection(by: offset)
    }

    public mutating func select(_ index: Int) {
        active.select(index)
    }

    /// Carries `previous`'s side and both panes' selections onto a rebuilt
    /// model, so the cursor stays put after a transfer. A selection that no
    /// longer exists is dropped by `select`'s bounds check.
    public mutating func restore(from previous: ContainerMenuModel) {
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
    /// owns both inventories. Both panes use the inventory builder, so both
    /// sort, name, and split gold the same way.
    public static func build(
        container: InventoryHolder,
        containerName: String,
        mode: Mode,
        pricing: BarterPricing,
        runtime: any InventoryAccess
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
