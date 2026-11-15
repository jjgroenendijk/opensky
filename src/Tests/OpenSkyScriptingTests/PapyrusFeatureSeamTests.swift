// The faction, relationship, and spellbook natives reach their features through the seams.

import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusFeatureSeamTests {
    private let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x900)
    private static let other = ReferenceKey.plugin(name: "base.esm", objectID: 0x901)
    private static let faction = ReferenceKey.plugin(name: "base.esm", objectID: 0x10)
    private static let spell = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func factionNativesGoThroughTheFactionSeam() {
        let factions = FakeFactionAccess()
        bridge.natives.faction = PapyrusFactionNatives(runtime: { _ in factions })
        #expect(bridge.factions.addToFaction(Self.actor, faction: Self.faction) == true)
        #expect(bridge.isInFaction(Self.actor, faction: Self.faction) == true)
        #expect(bridge.factions.addToFaction(Self.actor, faction: Self.faction) == false)
        #expect(bridge.factions.removeFromFaction(Self.actor, faction: Self.faction) == true)
        #expect(factions.left == [Self.faction])
    }

    @Test func relationshipNativesGoThroughTheRelationshipSeam() {
        let relationships = FakeRelationshipAccess()
        bridge.natives.faction = PapyrusFactionNatives(relationships: { relationships })
        #expect(bridge.factions.setRelationshipRank(3, of: Self.actor, toward: Self.other) == true)
        #expect(bridge.factions
            .relationshipRank(of: Self.actor, toward: Self.other) == .some(.some(3)))
    }

    @Test func spellNativesGoThroughTheSpellbookSeam() {
        let caster = FakeSpellCaster()
        bridge.natives.magic.casterRuntime = { caster }
        #expect(bridge.addSpell(Self.spell, to: bridge.playerKey))
        #expect(caster.spellbook.known[ActorValueHolder.player.key] == [Self.spell])
        #expect(bridge.removeSpell(Self.spell, from: bridge.playerKey))
        #expect(!bridge.removeSpell(Self.spell, from: bridge.playerKey))
    }

    @Test func aDiseaseThePlayerGainsShowsItsNotice() throws {
        typealias Fixture = SpellbookFixture
        let disease = Fixture.spell(
            formID: 0x0A10, editorID: "Rockjoint", equipType: Fixture.Slot.eitherHand,
            spit: Fixture.spit(type: 1, chargeTime: 0, casting: 0, delivery: 0)
        )
        let plain = Fixture.spell(
            formID: 0x0A11, editorID: "Sparks", equipType: Fixture.Slot.eitherHand,
            spit: Fixture.spit(type: 0, chargeTime: 0, casting: 1, delivery: 0)
        )
        let caster = FakeSpellCaster()
        caster.spellbook.spells = try SpellStore(
            index: Fixture.index(extraRecords: [disease, plain])
        )
        let presenter = FakePresenter()
        bridge.natives.magic.casterRuntime = { caster }
        bridge.ports.presenter = presenter

        #expect(bridge.addSpell(Fixture.key(0x0A11), to: bridge.playerKey))
        #expect(presenter.worldNotices.isEmpty)
        #expect(bridge.addSpell(Fixture.key(0x0A10), to: bridge.playerKey))
        #expect(!bridge.addSpell(Fixture.key(0x0A10), to: bridge.playerKey))
        #expect(presenter.worldNotices == [.diseaseContracted(name: "Rockjoint")])
    }
}
