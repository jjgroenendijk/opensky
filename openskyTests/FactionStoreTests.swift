// Synthetic load-order, editor-id, relation-join and SNAM template-inheritance
// coverage for FactionStore. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct FactionStoreTests {
    @Test
    func laterPluginWinsByIdentityAndEditorID() throws {
        let base = try plugin(factions: [
            FactionFixture.record(formID: 0x10, editorID: "OldName")
        ])
        let patch = try plugin(
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
        let file = try plugin(factions: [
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
    func membershipsInheritThroughTheTemplateFlagAndStopWhenItIsClear() throws {
        let file = try plugin(factions: [
            FactionFixture.record(
                formID: 0x10,
                editorID: "TemplateFaction",
                body: FactionFixture.rank(1, male: "Sergeant", female: "Sergeant")
            ),
            FactionFixture.record(formID: 0x11, editorID: "OwnFaction")
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])
        let template = try actor(
            formID: 0x600,
            editorID: "TemplateActor",
            factions: [(0x10, 1)]
        )
        let inheriting = try actor(
            formID: 0x601,
            editorID: "Inheriting",
            templateFlags: 0x0004,
            template: 0x600,
            factions: [(0x11, 0)]
        )
        let owning = try actor(
            formID: 0x602,
            editorID: "Owning",
            template: 0x600,
            factions: [(0x11, 0)]
        )
        let resolver = ActorTemplateResolver(
            actors: Dictionary(uniqueKeysWithValues: [template, inheriting, owning].map {
                ($0.formID.rawValue, $0)
            }),
            leveledActors: [:]
        )

        let inherited = store.memberships(
            ofBase: FormID(0x601),
            resolver: resolver,
            fromPlugin: "Base.esm"
        )
        #expect(inherited.map(\.faction?.editorID) == ["TemplateFaction"])
        #expect(inherited.map(\.rank) == [1])
        #expect(store.rankTitle(of: inherited[0], female: true) == LString.inline("Sergeant"))

        let own = store.memberships(
            ofBase: FormID(0x602),
            resolver: resolver,
            fromPlugin: "Base.esm"
        )
        #expect(own.map(\.faction?.editorID) == ["OwnFaction"])
        #expect(own.map(\.rank) == [0])
        #expect(store.rankTitle(of: own[0], female: false) == nil)
    }

    @Test
    func negativeRanksAndUnresolvedLinksSurviveTheJoin() throws {
        let file = try plugin(factions: [
            FactionFixture.record(formID: 0x10, editorID: "KnownFaction")
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])
        let npc = try actor(
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

    @Test
    func aBrokenTemplateChainYieldsNoMemberships() throws {
        let file = try plugin(factions: [
            FactionFixture.record(formID: 0x10, editorID: "KnownFaction")
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])
        let dangling = try actor(
            formID: 0x600,
            editorID: "Dangling",
            templateFlags: 0x0004,
            template: 0x999,
            factions: [(0x10, 0)]
        )
        let resolver = ActorTemplateResolver(
            actors: [dangling.formID.rawValue: dangling],
            leveledActors: [:]
        )

        #expect(store.memberships(
            ofBase: FormID(0x600),
            resolver: resolver,
            fromPlugin: "Base.esm"
        ).isEmpty)
    }

    private func actor(
        formID: UInt32,
        editorID: String,
        templateFlags: UInt16 = 0,
        template: UInt32? = nil,
        factions: [(faction: UInt32, rank: Int8)] = []
    ) throws -> ActorBase {
        try ActorBase(
            record: FactionFixture.decode(FactionFixture.actor(
                formID: formID,
                editorID: editorID,
                templateFlags: templateFlags,
                template: template,
                factions: factions
            )),
            localized: false
        )
    }

    private func plugin(masters: [String] = [], factions: [Data]) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        data += ESMFixture.topGroup("FACT", contents: factions.reduce(Data(), +))
        return try ESMFile(data: data)
    }

    private func id(_ plugin: String, _ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
