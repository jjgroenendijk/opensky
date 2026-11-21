// The magic menu's list movie on a synthetic `/Menu_mc` tree: the first rows slide the
// item panel out, and the selected spell's card goes to `UpdateItemCardInfo`.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyMagicInterface
@testable import OpenSkyMenus
import Testing

@MainActor
struct ItemListMenuSpellCardTests {
    private static func clip(_ name: String, in parent: SWFDisplayObject) -> SWFDisplayObject {
        let child = SWFDisplayObject(content: .clip(nil))
        child.name = name
        parent.addChild(child, atDepth: UInt16(parent.children.count + 1))
        return child
    }

    private static let flames = MagicMenuSpellCard(
        kind: .spell, effects: "Fire Damage 8", cost: 14, costIsPerSecond: true, level: "Novice"
    )

    private static func info(_ calls: MenuMovieCallLog) -> AS2Object? {
        calls.arguments(of: InventoryMenuMovieBridge.itemCardCallback)?.first?.objectValue
    }

    private static func value(_ name: String, in object: AS2Object?) -> AS2Value? {
        object?.lookup(name)?.property.value
    }

    @Test func theFirstRowsOpenThePanelAndSendTheSpellCard() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let menu = Self.clip("Menu_mc", in: runtime.root)
        let lists = Self.clip("InventoryLists_mc", in: menu)
        let card = Self.clip("ItemCard_mc", in: Self.clip("ItemCardFadeHolder_mc", in: menu))
        let panel = MenuMovieCallLog(runtime: runtime, names: ["ShowItemsList"], on: lists)
        let fade = MenuMovieCallLog(runtime: runtime, names: ["FadeInCard"], on: card)
        let root = MenuMovieCallLog(
            runtime: runtime, names: [InventoryMenuMovieBridge.itemCardCallback]
        )
        ItemListMenuMovieBridge.prepare(runtime: runtime)
        ItemListMenuMovieBridge.publish([
            ItemListCategory(label: "All", rows: [
                ItemListRow(tag: 0, name: "Flames", spellCard: Self.flames)
            ])
        ], runtime: runtime)
        #expect(panel.names == ["ShowItemsList"])
        #expect(fade.names == ["FadeInCard"])
        let info = Self.info(root)
        #expect(Self.value("type", in: info) == .integer(InventoryMenuMovieBridge.spellType))
        #expect(Self.value("spellCost", in: info) == .integer(14))
        // Concentration: 0 picks the movie's per-second layout.
        #expect(Self.value("castTime", in: info) == .integer(0))
        #expect(Self.value("castLevel", in: info) == .string("Novice"))
        #expect(ItemListMenuMovieBridge.rowLabels(runtime: runtime).rows.isEmpty)
    }

    @Test func aPowerShowsNoCostAndARowWithoutACardHidesIt() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let root = MenuMovieCallLog(
            runtime: runtime, names: [InventoryMenuMovieBridge.itemCardCallback]
        )
        let power = MagicMenuSpellCard(
            kind: .power, effects: "Fortify", cost: 0, costIsPerSecond: false, level: "Novice"
        )
        InventoryMenuMovieBridge.publishSpellCard(power, name: "Battle Cry", runtime: runtime)
        #expect(
            Self.value("type", in: Self.info(root))
                == .integer(InventoryMenuMovieBridge.spellDefaultType)
        )
        #expect(Self.value("spellCost", in: Self.info(root)) == nil)
        InventoryMenuMovieBridge.publishSpellCard(nil, name: "Unrelenting Force", runtime: runtime)
        #expect(Self.value("type", in: Self.info(root)) == .integer(0))
    }

    @Test func aGiftListSendsNoCard() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let root = MenuMovieCallLog(
            runtime: runtime, names: [InventoryMenuMovieBridge.itemCardCallback]
        )
        ItemListMenuMovieBridge.publish([
            ItemListCategory(label: "All", rows: [ItemListRow(tag: 7, name: "Iron Dagger")])
        ], runtime: runtime)
        #expect(root.names.isEmpty)
    }
}
