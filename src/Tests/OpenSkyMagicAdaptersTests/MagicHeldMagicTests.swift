// The held magic part holds, throws, and lights actors, and places hazards.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
@testable import OpenSkyMagicAdapters
import OpenSkyMagicInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct MagicHeldMagicTests {
    private let host = MagicHost()
    private var adapter: MagicWorldAdapter {
        MagicWorldAdapter(game: host)
    }

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let moved = ReferenceTransformOverride(
        position: SIMD3(100, 0, 0), rotation: .zero, scale: 1
    )

    init() {
        host.fakeCombat.meleeAttackerValue = MeleeAttacker(key: .player, feet: .zero, facing: 0)
    }

    @Test func livingActorsAreFoundAroundAMovedNPC() {
        host.fakeStreamer.npcTransformResult = Self.moved
        #expect(adapter.livingActors(near: Self.actor, radius: 150) == [.player])
        #expect(adapter.livingActors(near: Self.actor, radius: 50).isEmpty)
        #expect(adapter.livingActors(near: .player, radius: 150).isEmpty)
    }

    @Test func raceAndEatingGoThroughTheirPorts() {
        host.fakeMenuWorld.setRaceResult = true
        #expect(adapter.changeRace(of: Self.actor, to: FormID(0x50)))
        #expect(host.fakeMenuWorld.setRaceCalls.map(\.race) == [FormID(0x50)])
        adapter.markEaten(Self.actor)
    }

    @Test func aLetGoActorIsSetDownAndReleased() {
        host.fakeStreamer.npcTransformResult = Self.moved
        let adapter = adapter
        adapter.state.grabbedActors = [Self.actor]
        adapter.holdActor(Self.actor, at: nil)
        #expect(host.fakeStreamer.steerRiddenActorCalls.count == 1)
        #expect(host.fakeStreamer.releaseRiddenActorCalls == [Self.actor])
        #expect(adapter.state.grabbedActors.isEmpty)
    }

    @Test func anActorTheStreamerCannotHoldStaysFree() {
        adapter.holdActor(Self.actor, at: SIMD3(1, 2, 3))
        adapter.holdActor(.player, at: SIMD3(1, 2, 3))
        #expect(host.fakeStreamer.takeRiddenActorCalls == [Self.actor])
        #expect(host.fakeStreamer.steerRiddenActorCalls.isEmpty)
    }

    @Test func aThrownNPCIsKnockedDownAlongTheThrow() {
        host.fakeStreamer.npcTransformResult = Self.moved
        adapter.throwActor(Self.actor, along: SIMD3(1, 0, 0), force: 5)
        adapter.throwActor(Self.actor, along: SIMD3(0, 0, 1), force: 5)
        adapter.throwActor(.player, along: SIMD3(1, 0, 0), force: 5)
        #expect(host.fakeEffectsWorld.knockDownCalls.count == 1)
    }

    @Test func withoutAMarkerOrAStoreNothingIsGuidedOrPlaced() {
        #expect(adapter.guidePath(for: Self.actor) == .noMarker)
        #expect(adapter.guidePath(for: .player) == .noMarker)
        #expect(!adapter.placeHazard(Self.actor, at: .zero))
        #expect(adapter.aimRay(of: .player) == nil)
        #expect(adapter.telekinesisTarget(for: .player, within: 100) == nil)
    }

    @Test func anEndedCastingLightIsForgotten() {
        let adapter = adapter
        let held = adapter.heldMagic
        adapter.state.castingLights[Self.actor] = Self.actor
        held.showCastingLight(FormID(0x70), plugin: "base.esm", caster: Self.actor, shown: false)
        #expect(adapter.state.castingLights.isEmpty)
        held.publishMagicLights()
        held.publishSummonFades()
    }

    @Test func theHazardClockStepsOnlyWhileTheWorldRuns() {
        var now = Date(timeIntervalSinceReferenceDate: 100)
        let hazards = HazardWorldAdapter(HazardWorldDependencies(
            hazards: { HazardCoordinator() }, combat: host.fakeCombat,
            magic: { preconditionFailure("not read") }, spellHits: { adapter },
            gameSession: { nil }, now: { now }
        ))
        hazards.tick(paused: false)
        now += 1
        hazards.tick(paused: false)
        #expect(hazards.lastFrame == now)
        hazards.tick(paused: true)
        #expect(hazards.lastFrame == nil)
        #expect(hazards.hazardSpec(for: Self.actor) == nil)
        #expect(hazards.hazardModelPath(for: Self.actor) == nil)
        #expect(hazards.hazardCandidates().isEmpty)
    }
}
