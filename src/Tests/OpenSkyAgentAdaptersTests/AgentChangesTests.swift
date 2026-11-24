import Foundation

// The debug commands that change the world as a script would reach the Papyrus world bridge
// with the forms they name, and `state music` shows the music director's readout.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
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

    @Test func aDeletionAndALockAreWrittenForTheReference() throws {
        let deleted = try result(.delete(reference: "B8780"))
        #expect(bridge.writeCalls.map(\.key) == [spell])
        #expect(deleted["deleted"] == .bool(true))
        bridge.lockStateResult = ReferenceLockState(isLocked: true, level: 50, key: nil)
        let unlocked = try result(.lock(reference: "B8780", locked: false))
        #expect(unlocked["locked"] == .bool(false))
        #expect(unlocked["level"] == .init(50))
        bridge.lockStateResult = nil
        #expect(try result(.lock(reference: "B8780", locked: true))["level"] == .init(1))
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.delete(reference: "player")))
        }
    }

    @Test func aReleaseNeedsAPlayingSound() throws {
        let loop = try PlayingLoopSession()
        let id = loop.id
        host.gameSession = loop.session
        #expect(try result(.release(sound: id))["released"] == .bool(true))
        #expect(throws: AgentFailure.self) { try world.perform(.world(.release(sound: id + 1))) }
    }

    @Test func aGrabHoldsTheReferenceAndNoReferenceLetsGo() throws {
        host.fakePlayerGrab.grabReadout = PlayerGrabReadout(
            isEnabled: true, phase: "holding", held: 0xB8780, distance: 80,
            strength: GrabStrength(force: 1, elasticity: 1)
        )
        host.fakePlayerGrab.grabResult = true
        let held = try result(.grab(reference: "B8780"))
        #expect(host.fakePlayerGrab.grabCalls == [spell])
        #expect(held["phase"] == .string("holding"))
        #expect(held["held"] == .formID(0xB8780))
        _ = try result(.grab(reference: nil))
        #expect(host.fakePlayerGrab.letGoCallCount == 1)
        host.fakePlayerGrab.grabResult = false
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.grab(reference: "B8780")))
        }
    }

    @Test func anActivationReachesTheBridgeAsAScriptWould() throws {
        bridge.activateResult = PapyrusActivationOutcome(
            recorded: true, queuedEvents: 2, cappedByRecursion: false
        )
        let answer = try result(.activate(reference: "B8780", activator: "player"))
        #expect(bridge.activateCalls.map(\.target) == [spell])
        #expect(bridge.activateCalls.map(\.activator) == [.player])
        #expect(bridge.activateCalls.map(\.togglesOpen) == [false])
        #expect(answer["queuedEvents"] == .init(2))
        #expect(answer["cappedByRecursion"] == .bool(false))
    }

    @Test func aSpawnAnswersTheNewReference() throws {
        bridge.spawnReferenceOfAtResult = .generated(4)
        let answer = try result(.spawn(base: "B8780", anchor: "player"))
        #expect(bridge.spawnReferenceOfAtCalls.map(\.anchor) == [.player])
        #expect(answer["ref"] == .formID(0xFF00_0004))
    }

    @Test func aSpawnAtThePlayerStandsInFrontFacingBack() throws {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: .zero, yaw: 0, pitch: 0)
        let walk = FakeWalkPort()
        walk.feetPosition = [10, 20, 30]
        session.walkController = walk
        host.gameSession = session
        bridge.spawnReferenceOfPlacementResult = .generated(5)
        let answer = try result(.spawn(base: "B8780", anchor: "player"))
        let placement = try #require(bridge.spawnReferenceOfPlacementCalls.first?.placement)
        #expect(placement.position == [138, 20, 30])
        #expect(abs(placement.rotation.z + .pi / 2) < 1e-5)
        #expect(bridge.spawnReferenceOfAtCalls.isEmpty)
        #expect(answer["ref"] == .formID(0xFF00_0005))
    }

    @Test func aSpawnThatFindsNoPlaceFails() {
        #expect(throws: AgentFailure.self) {
            try result(.spawn(base: "B8780", anchor: "player"))
        }
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

    @Test func aDetectionEventSoundsAtThePlayersFeet() throws {
        #expect(throws: AgentFailure.self) {
            try world.perform(.world(.detectionEvent(level: 50)))
        }
        let perception = FakePerceptionRuntimePort()
        host.fakePerception.runtime = perception
        let session = FakeGameSessionPort()
        let walk = FakeWalkPort()
        walk.feetPosition = SIMD3(10, 0, 0)
        session.walkController = walk
        host.gameSession = session
        let state = try result(.detectionEvent(level: 50))
        #expect(state["level"] == .init(Float(50)))
        #expect(perception.noteSoundEventCalls.map(\.position) == [SIMD3(10, 0, 0)])
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
