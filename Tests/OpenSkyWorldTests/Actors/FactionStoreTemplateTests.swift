// Faction memberships inherited through the actor template chain. In-code plugin fixtures only.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct FactionStoreTemplateTests {
    @Test
    func membershipsInheritThroughTheTemplateFlagAndStopWhenItIsClear() throws {
        let file = try FactionFixture.plugin(factions: [
            FactionFixture.record(
                formID: 0x10,
                editorID: "TemplateFaction",
                body: FactionFixture.rank(1, male: "Sergeant", female: "Sergeant")
            ),
            FactionFixture.record(formID: 0x11, editorID: "OwnFaction")
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])
        let template = try FactionFixture.actorBase(
            formID: 0x600,
            editorID: "TemplateActor",
            factions: [(0x10, 1)]
        )
        let inheriting = try FactionFixture.actorBase(
            formID: 0x601,
            editorID: "Inheriting",
            templateFlags: 0x0004,
            template: 0x600,
            factions: [(0x11, 0)]
        )
        let owning = try FactionFixture.actorBase(
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
    func aBrokenTemplateChainYieldsNoMemberships() throws {
        let file = try FactionFixture.plugin(factions: [
            FactionFixture.record(formID: 0x10, editorID: "KnownFaction")
        ])
        let store = FactionStore(plugins: [("Base.esm", file)])
        let dangling = try FactionFixture.actorBase(
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
}
