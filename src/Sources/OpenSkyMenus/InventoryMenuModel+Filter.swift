// The tab bits of the vanilla item movies. A category row with a `flag` of 0 draws
// as a divider. See docs/engine/inventory-menu.md#list-data.

nonisolated extension InventoryMenuModel {
    /// The movie's bit for the tab at `index`.
    public static func categoryFlag(_ index: Int) -> Int {
        index < 31 ? 1 << index : 0
    }
}
