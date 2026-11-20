// `menu magic`: drive `magicmenu.swf` through `ItemListMenuMovieBridge` with a
// seeded spell list, and print the rows the movie drew. The rows are made up:
// the probe checks the movie's list plumbing, not the player's spells.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsSWF
import OpenSkyMagicInterface
import OpenSkyMenus

enum SWFMagicMenuCommand {
    static func run(context: CLIContext, arguments: MenuArguments.Magic) throws {
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: context.makeFileSystem())
                .load(path: ItemListMenuMovieBridge.magicMoviePath)
        )
        ItemListMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        ItemListMenuMovieBridge.activate(runtime: runtime)
        for _ in 0 ..< arguments.drive.ticks {
            runtime.advance()
        }
        ItemListMenuMovieBridge.publish(seed, runtime: runtime)
        for _ in 0 ..< arguments.drive.ticks {
            runtime.advance()
        }
        let labels = ItemListMenuMovieBridge.rowLabels(runtime: runtime)
        let bridge = InventoryMenuMovieBridge.self
        print("[INFO] menu magic categories: \(labels.categories.joined(separator: ", "))")
        print("[INFO] menu magic rows: \(labels.rows.joined(separator: ", "))")
        let state = ItemCardSubMenuBridge.listsState(runtime: runtime).map(String.init) ?? "none"
        print("[INFO]   movie lists state: \(state)")
        let categories = bridge.shownClipCount(runtime: runtime, atPath: bridge.categoryListPath)
        let rows = bridge.shownClipCount(runtime: runtime, atPath: bridge.itemListPath)
        print("[INFO]   category clips shown: \(categories)")
        print("[INFO]   row clips shown: \(rows)")
        print("[INFO]   item card shown: \(ItemCardSubMenuBridge.isCardVisible(runtime: runtime))")
        let card = runtime.node(atPath: ItemCardSubMenuBridge.itemCardPath, from: runtime.root)
        print("[INFO]   item card texts: \(texts(under: card).joined(separator: " | "))")
        let diagnostics = bridge.diagnostics(runtime: runtime)
        print(
            "[INFO] menu magic diagnostics: \(runtime.nodeCount) nodes, "
                + "\(diagnostics.faults) faults, "
                + "\(diagnostics.unhandledInvokes) unhandled of "
                + "\(runtime.invokeLog.total) invokes"
        )
        for entry in runtime.invokeLog.entries where !entry.isHandled {
            print("[INFO]   unhandled \(entry.direction.rawValue) \(entry.name)")
        }
    }

    /// The non-empty texts under `node` that are drawn, in paint order.
    private static func texts(under node: SWFDisplayObject?) -> [String] {
        guard let node, node.isVisible else { return [] }
        let own = node.textOverride.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return (own.isEmpty ? [] : [own]) + node.children.flatMap { texts(under: $0) }
    }

    private static let flames = ItemListRow(
        tag: 0, name: "Flames", isEquipped: true, spellCard: MagicMenuSpellCard(
            kind: .spell, effects: "Fire Damage 8", cost: 14, costIsPerSecond: true,
            level: "Novice"
        )
    )
    private static let healing = ItemListRow(tag: 1, name: "Healing", spellCard: MagicMenuSpellCard(
        kind: .spell, effects: "Restore Health 10", cost: 12, costIsPerSecond: true,
        level: "Novice"
    ))
    private static let seed = [
        ItemListCategory(label: "All", rows: [flames, healing]),
        ItemListCategory(label: "Destruction", rows: [flames]),
        ItemListCategory(label: "Restoration", rows: [healing])
    ]
}
