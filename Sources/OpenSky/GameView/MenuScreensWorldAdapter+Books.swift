// The book menu's reads: the BOOK record's text from the strings files, the books the
// player carries, and what reading one teaches through the magic coordinator.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus

extension MenuScreensWorldAdapter: BookMenuWorld {
    private var items: ItemDefinitionStore? {
        game.inventory.runtime?.inventory.baselines.items
    }

    func bookContent(_ item: FormID) -> BookContent? {
        guard let book = items?.books[item.rawValue] else { return nil }
        return BookContent(
            title: game.inventory.name(of: item),
            text: game.mapWorld.text(book.text, kind: .dlstrings) ?? "",
            isNote: book.kind == .note
        )
    }

    func readBook(_ item: FormID) -> String? {
        game.magic.readBook(item)?.text
    }

    var carriedBooks: [FormID] {
        guard let runtime = game.inventory.runtime, let items else { return [] }
        return runtime.inventory.inventory(of: .player).stacks
            .map(\.item)
            .filter { items.books[$0.rawValue] != nil }
            .sorted { $0.rawValue < $1.rawValue }
    }
}
