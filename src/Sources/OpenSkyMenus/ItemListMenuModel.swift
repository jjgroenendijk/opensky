// The rows of a list menu that is not the inventory: the magic menu's spells and the
// gift menu's items. Categories hold rows; the engine owns the selection.

import Foundation

nonisolated public struct ItemListRow: Equatable, Sendable {
    /// What the screen's world finds the row's thing by: an item's FormID, or a spell's
    /// position in the known list.
    public var tag: UInt32
    public var name: String
    public var count: Int32
    public var isEquipped: Bool

    public init(tag: UInt32, name: String, count: Int32 = 1, isEquipped: Bool = false) {
        self.tag = tag
        self.name = name
        self.count = count
        self.isEquipped = isEquipped
    }

    /// The row as the text panel lists it.
    public var line: String {
        let count = count > 1 ? " (\(count))" : ""
        return "\(name)\(count)\(isEquipped ? "  [equipped]" : "")"
    }
}

nonisolated public struct ItemListCategory: Equatable, Sendable {
    public var label: String
    public var rows: [ItemListRow]

    public init(label: String, rows: [ItemListRow]) {
        self.label = label
        self.rows = rows
    }
}

nonisolated public struct ItemListMenuModel: Equatable, Sendable {
    public private(set) var categories: [ItemListCategory]
    public private(set) var selectedCategory = 0
    public private(set) var selectedRow = 0

    public init(categories: [ItemListCategory]) {
        self.categories = categories
    }

    public var rows: [ItemListRow] {
        categories.indices.contains(selectedCategory) ? categories[selectedCategory].rows : []
    }

    public var selected: ItemListRow? {
        rows.indices.contains(selectedRow) ? rows[selectedRow] : nil
    }

    public mutating func moveCategory(by step: Int) {
        guard !categories.isEmpty else { return }
        selectedCategory = (selectedCategory + step + categories.count) % categories.count
        selectedRow = 0
    }

    public mutating func moveRow(by step: Int) {
        selectRow(selectedRow + step)
    }

    public mutating func selectRow(_ index: Int) {
        selectedRow = rows.isEmpty ? 0 : min(max(index, 0), rows.count - 1)
    }

    /// New rows keep the category and the nearest row.
    public mutating func replace(_ categories: [ItemListCategory]) {
        self.categories = categories
        selectedCategory = min(selectedCategory, max(0, categories.count - 1))
        selectRow(selectedRow)
    }
}
