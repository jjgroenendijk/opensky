// A quest alias gives its reference factions, spells, and items on entering and takes
// the factions and spells back on leaving. See docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyQuests
import OpenSkySessionTesting
@testable import OpenSkyStoryAdapters
import OpenSkyWorldState
import Testing

@MainActor
struct StoryAliasDataTests {
    private let host = StoryHost()
    private let adapter: StoryWorldAdapter
    private let bridge = FakePapyrusWorldStateBridgePort()
    private let items = FakeInventoryScriptItemsPort()
    private static let reference = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let faction = ResolvedFormID(plugin: "base.esm", objectID: 0x30)
    private static let spell = ResolvedFormID(plugin: "base.esm", objectID: 0x31)
    private static let item = ResolvedFormID(plugin: "base.esm", objectID: 0x32)

    init() {
        adapter = StoryWorldAdapter(
            game: host,
            stage: nil,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        bridge.formIDResolver = FormIDResolver(pluginName: "base.esm", masters: [])
        host.fakeScripts.bridge = bridge
        host.fakeInventory.scriptItems = items
    }

    private static func change(entered: Bool) -> QuestAliasDataChange {
        QuestAliasDataChange(
            reference: reference,
            entered: entered,
            factions: [faction],
            spells: [spell],
            items: entered ? [.init(item: item, count: 2)] : []
        )
    }

    @Test func enteringAnAliasGivesItsFactionsSpellsAndItems() {
        adapter.giveAliasData([Self.change(entered: true)])

        #expect(bridge.addToFactionCalls.map(\.faction) == [ReferenceKey(resolved: Self.faction)])
        #expect(bridge.addToFactionCalls.map(\.actor) == [Self.reference])
        #expect(bridge.addSpellCalls.map(\.spell) == [ReferenceKey(resolved: Self.spell)])
        #expect(items.scriptAddItemCalls.map(\.item) == [FormID(0x32)])
        #expect(items.scriptAddItemCalls.map(\.count) == [2])
        #expect(bridge.removeFromFactionCalls.isEmpty)
    }

    @Test func leavingAnAliasTakesItsFactionsAndSpells() {
        adapter.giveAliasData([Self.change(entered: false)])

        #expect(bridge.removeFromFactionCalls.map(\.actor) == [Self.reference])
        #expect(bridge.removeSpellCalls.map(\.spell) == [ReferenceKey(resolved: Self.spell)])
        #expect(bridge.addToFactionCalls.isEmpty)
        #expect(items.scriptAddItemCalls.isEmpty)
    }

    @Test func withoutAScriptBridgeNothingIsGiven() {
        host.fakeScripts.bridge = nil
        adapter.giveAliasData([Self.change(entered: true)])
        #expect(items.scriptAddItemCalls.isEmpty)
    }
}
