// Inventory menu seam: menu-stack state, engine rows, and movie state, without
// exposing `GameViewController`. Same shape as `SystemMenuControlProviding`.

import Foundation

nonisolated public struct InventoryMenuControlSnapshot: Equatable, Sendable {
    /// One line per row of the selected category, already formatted.
    public let entryLines: [String]
    public let selectedIndex: Int

    public init(
        entryLines: [String],
        selectedIndex: Int
    ) {
        self.entryLines = entryLines
        self.selectedIndex = selectedIndex
    }
}
