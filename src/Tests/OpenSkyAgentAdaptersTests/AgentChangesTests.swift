import Foundation

// The debug commands that change the world as a script would reach the Papyrus world bridge
// with the forms they name, and `state music` shows the music director's readout.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AgentChangesTests {
    private let host = AgentHost()
    private let bridge = FakePapyrusWorldStateBridgePort()
    private let world: AgentWorldAdapter
    private let spell = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0xB8780)

    init() {
        host.fakeScripts.bridge = bridge
        bridge.referenceKeyResult = spell
        bridge.localFormIDResult = FormID(0xB8780)
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func result(_ change: AgentWorldChange) throws -> [String: AgentJSON] {
        guard
            case let .done(.success(.object(fields))) = try world.perform(.world(change))
        else {
            Issue.record("no answer")
            return [:]
        }
        return fields
    }

    @Test func aSpellReachesThePlayersSpellbook() throws {
        bridge.addSpellResult = true
        let answer = try result(.spell(spell: "B8780", reference: "player", known: true))
        #expect(bridge.addSpellCalls.map(\.actor) == [.player])
        #expect(bridge.referenceKeyCalls == [FormID(0xB8780)])
        #expect(answer["changed"] == .bool(true))
        _ = try result(.spell(spell: "B8780", reference: "player", known: false))
        #expect(bridge.removeSpellCalls.count == 1)
    }

    @Test func aCastNamesTheCasterAndTheTarget() throws {
        bridge.castSpellResult = true
        _ = try result(.cast(spell: "B8780", caster: "player", target: "B8780"))
        #expect(bridge.castSpellCalls.first?.source == .player)
        #expect(bridge.castSpellCalls.first?.target == spell)
        bridge.castSpellResult = false
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.cast(spell: "B8780", caster: "player", target: nil)))
        }
    }

    @Test func enableStateIsWrittenForAnyReference() throws {
        let answer = try result(.enable(reference: "B8780", enabled: false))
        #expect(bridge.writeCalls.map(\.key) == [spell])
        #expect(answer["enabled"] == .bool(false))
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.enable(reference: "player", enabled: false)))
        }
    }

    @Test func aSpawnAnswersTheNewReference() throws {
        bridge.spawnReferenceResult = .generated(4)
        let answer = try result(.spawn(base: "B8780", anchor: "player"))
        #expect(bridge.spawnReferenceCalls.map(\.anchor) == [.player])
        #expect(answer["ref"] != nil)
    }

    @Test func aModifierStartsAndStopsOnTheImageSpace() throws {
        let session = FakeGameSessionPort()
        session.imageSpaceValue = ImageSpaceState()
        host.gameSession = session
        host.fakeEffects.startModifierResult = true
        let request = AgentModifierRequest(
            modifier: "B8780", strength: 0.5, fadeSeconds: 2, crossFade: true, remove: false
        )
        _ = try result(.imageSpaceModifier(request))
        #expect(host.fakeEffects.startModifierCalls.first?.strength == 0.5)
        let off = AgentModifierRequest(
            modifier: "B8780", strength: 1, fadeSeconds: 1, crossFade: false, remove: true
        )
        _ = try result(.imageSpaceModifier(off))
        #expect(host.fakeEffects.stopModifierCalls.count == 1)
        host.fakeEffects.startModifierResult = false
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.imageSpaceModifier(request)))
        }
    }

    @Test func aDecalStrikesTheActorsSideFacingThePlayer() throws {
        host.fakeEffects.skinDecalsValue = SkinDecalRuntime()
        host.fakeActorWorld.combatActorResult = CombatActorObservation(
            key: .generated(9), feet: [10, 0, 0], name: "guard"
        )
        host.fakeCombatWorld.impactMaterialResult = FormID(0x1F)
        host.fakeCombatWorld.impactDataSetEditorIDMaterialResult = ResolvedMeleeImpact(
            sound: FormID(0x2)
        )
        let state = try result(.decal(reference: "player", height: 100))
        let lookup = try #require(host.fakeCombatWorld.impactDataSetEditorIDMaterialCalls.first)
        #expect(lookup.material == FormID(0x1F))
        let call = try #require(host.fakeCombatWorld.playImpactImpactAtCalls.first)
        #expect(call.impact.target == .player)
        #expect(call.position.z == 100)
        #expect(state["placed"] == .bool(false))
        #expect(state["skinDecals"] == .array([]))
        host.fakeCombatWorld.impactDataSetEditorIDMaterialResult = nil
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.decal(reference: "player", height: 100)))
        }
    }

    @Test func aDecalNeedsALoadedActor() {
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.decal(reference: "player", height: 100)))
        }
    }

    @Test func formsMustBeHexAndKnown() {
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.spell(spell: "Flames", reference: "player", known: true)))
        }
        bridge.referenceKeyResult = nil
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.spell(spell: "B8780", reference: "player", known: true)))
        }
        host.fakeScripts.bridge = nil
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.spell(spell: "B8780", reference: "player", known: true)))
        }
    }

    @Test func musicWithoutADirectorIsNull() throws {
        let state = try world.query(.music)
        #expect(state == ["music": .null])
    }

    @Test func musicShowsTheDirectorsReadout() throws {
        let director = FakeWorldMusicDirectorPort()
        var readout = MusicReadout()
        readout.musicType = "MUSDungeon"
        readout.state = "dungeon"
        readout.trackPath = "music\\dungeon\\a.xwm"
        readout.paused = true
        director.readoutValue = readout
        host.fakeAudio.musicDirector = director
        let state = try world.query(.music)
        #expect(state["musicType"] == .string("MUSDungeon"))
        #expect(state["state"] == .string("dungeon"))
        #expect(state["track"] == .string("music\\dungeon\\a.xwm"))
        #expect(state["paused"] == .bool(true))
        #expect(state["musicTypeFormID"] == .null)
    }
}
