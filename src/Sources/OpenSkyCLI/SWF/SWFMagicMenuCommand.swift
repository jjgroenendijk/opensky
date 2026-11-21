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
        ItemListMenuMovieBridge.publish(seed, row: arguments.drive.down, runtime: runtime)
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
        let shown = own.isEmpty ? [] : [node.name.map { "\($0)=\(own)" } ?? own]
        return shown + node.children.flatMap { texts(under: $0) }
    }

    private static let flames = ItemListRow(
        tag: 0, name: "Flames", isEquipped: true, spellCard: MagicMenuSpellCard(
            kind: .spell, effects: "Fire Damage 8", cost: 14, costIsPerSecond: true,
            level: "Novice"
        )
    )
    private static let healing = ItemListRow(tag: 1, name: "Healing", spellCard: MagicMenuSpellCard(
        kind: .spell, effects: "Restore Health 10", cost: 12, costIsPerSecond: false,
        level: "Novice"
    ))
    private static let force = ItemListRow(
        tag: 2,
        name: "Unrelenting Force",
        spellCard: MagicMenuSpellCard(
            kind: .shout(words: [
                MagicMenuShoutWord(dragon: "Fus", translation: "Force", isUnlocked: true),
                MagicMenuShoutWord(dragon: "Ro", translation: "Balance", isUnlocked: false),
                MagicMenuShoutWord(dragon: "Dah", translation: "Push", isUnlocked: false)
            ]),
            effects: "Your Voice is raw power, pushing aside anything that stands in your path.",
            cost: 15
        )
    )
    private static let fortify = ItemListRow(
        tag: 3,
        name: "Fortify Health",
        spellCard: MagicMenuSpellCard(
            kind: .activeEffect(secondsLeft: 95), effects: "Health is increased by 20 points."
        )
    )
    private static let seed = [
        ItemListCategory(label: "All", rows: [flames, healing, force, fortify]),
        ItemListCategory(label: "Destruction", rows: [flames]),
        ItemListCategory(label: "Restoration", rows: [healing]),
        ItemListCategory(label: "Shouts", rows: [force]),
        ItemListCategory(label: "Active Effects", rows: [fortify])
    ]
}
