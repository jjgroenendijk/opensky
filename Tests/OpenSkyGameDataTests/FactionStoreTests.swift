// Synthetic load-order, editor-id, relation-join and SNAM template-inheritance
// coverage for FactionStore. No game-derived bytes.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct FactionStoreTests {
    @Test
    func laterPluginWinsByIdentityAndEditorID() throws {
        let base = try FactionFixture.plugin(factions: [
            FactionFixture.record(formID: 0x10, editorID: "OldName")
        ])
        let patch = try FactionFixture.plugin(
            masters: ["Base.esm"],
            factions: [FactionFixture.record(formID: 0x10, editorID: "NewName")]
        )
        let store = FactionStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(store.faction(id("Base.esm", 0x10)))
        #expect(resolved.editorID == "NewName")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.faction(editorID: "newname")?.id == resolved.id)
        #expect(store.faction(editorID: "OldName") == nil)
        #expect(store.factions.count == 1)
    }

    @Test
    func classifiesVendorAndCrimeFactionsAndJoinsRelations() throws {
        let file = try FactionFixture.plugin(factions: [
            FactionFixture.record(
                formID: 0x10,
                editorID: "GuardFaction",
                body: FactionFixture.flags(0x0000_0040)
                    + FactionFixture.relation(0x11, modifier: 0, reaction: 1)
                    + FactionFixture.relation(0x99, modifier: 0, reaction: 1)
            ),
            FactionFixture.record(
                formID: 0x11,
                editorID: "MerchantFaction",
                body: FactionFixture.flags(0x0000_4000) + FactionFixture.vendorValues()
            )
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])

        #expect(store.crimeFactions.map(\.editorID) == ["GuardFaction"])
        #expect(store.vendorFactions.map(\.editorID) == ["MerchantFaction"])
        #expect(store.sortedFactions.map(\.editorID) == ["GuardFaction", "MerchantFaction"])

        let guards = try #require(store.faction(editorID: "GuardFaction"))
        let joined = store.relations(of: guards)
        #expect(joined.count == 2)
        #expect(joined[0].faction?.editorID == "MerchantFaction")
        #expect(joined[0].relation.reaction == .enemy)
        // A relation may name a RACE, so an unresolved entry is normal.
        #expect(joined[1].faction == nil)
        #expect(store.displayString(for: FormID(0x11), fromPlugin: "Base.esm")
            == "MerchantFaction")
        #expect(store.displayString(for: FormID(0x99), fromPlugin: "Base.esm")
            == "[UNRESOLVED] 00000099")
    }

    @Test
    func negativeRanksAndUnresolvedLinksSurviveTheJoin() throws {
        let file = try FactionFixture.plugin(factions: [
            FactionFixture.record(formID: 0x10, editorID: "KnownFaction")
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])
        let npc = try FactionFixture.actorBase(
            formID: 0x600,
            editorID: "Outsider",
            factions: [(0x10, -1), (0x99, 3)]
        )
        let resolved = store.memberships(npc.factions, fromPlugin: "Base.esm")

        #expect(npc.factions.map(\.rank) == [-1, 3])
        #expect(resolved[0].isResolved)
        #expect(resolved[0].displayName == "KnownFaction")
        #expect(store.rankTitle(of: resolved[0], female: false) == nil)
        #expect(!resolved[1].isResolved)
        #expect(resolved[1].displayName == "[UNRESOLVED] 00000099")
    }

    private func id(_ plugin: String, _ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
