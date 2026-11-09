// The effects world runs trap scripts: motion, resets, pushes, effects, and placements.

import Foundation
import OpenSkyCombatAdapters
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct EffectsTrapControlTests {
    private let host = CombatHost()
    private let adapter: EffectsWorldAdapter

    private static let trap = ReferenceKey.plugin(name: "base.esm", objectID: 0x30)
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let cell = CellSceneLocation.interior(FormID(0x100))

    init() {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        adapter = EffectsWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func aMotionTypeNeedsALoadedCell() {
        #expect(!adapter.setMotionType(.keyframed, of: Self.trap))
        host.fakeStreamer.cellLocationResult = Self.cell
        #expect(adapter.setMotionType(.dynamic, of: Self.trap))
        #expect(adapter.setMotionType(.keyframed, of: Self.trap))
    }

    @Test func aResetWithoutATargetDropsTheMovedPose() {
        #expect(adapter.resetReference(Self.trap, to: nil))
        #expect(adapter.resetReference(Self.trap, to: Self.actor))
        #expect(host.fakeWorldState.resetKindForCalls.map(\.key) == Array(
            repeating: Self.trap, count: 4
        ))
    }

    @Test func withoutRecordsOrABridgeNothingFiresOrSpawns() {
        #expect(!adapter.fireWeapon(Self.trap, from: Self.trap, ammunition: nil))
        #expect(adapter.placeAtMe(Self.trap, at: Self.trap, count: 2) == nil)
        #expect(!adapter.applyImpulse(SIMD3(1, 0, 0), to: Self.trap))
        #expect(!adapter.pushActor(Self.actor, awayFrom: Self.trap, along: nil, speed: 0))
        #expect(!adapter.pushActor(Self.actor, awayFrom: Self.trap, along: nil, speed: 5))
        #expect(!adapter.knockDownActor(Self.actor, awayFrom: Self.trap, magnitude: 1))
    }

    @Test func aStaggerGoesThroughTheMagicWorld() {
        host.fakeMagicWorld.staggerActorResult = true
        #expect(adapter.staggerActor(Self.actor, magnitude: 0.5))
        #expect(host.fakeMagicWorld.staggerActorCalls.map(\.key) == [Self.actor])
    }

    @Test func effectsAttachAndDetachOnTheActor() {
        host.fakeEffects.attachResult = 1
        host.fakeEffects.detachResult = 1
        #expect(adapter.playEffect(Self.trap, on: Self.actor, duration: 2, facing: nil))
        #expect(adapter.stopEffect(Self.trap, on: Self.actor))
        #expect(host.fakeEffects.attachCalls.count == 1)
        #expect(host.fakeEffects.detachCalls.map(\.key) == [Self.trap])
    }

    @Test func imageSpaceModifiersNeedASession() {
        #expect(!adapter.applyImageSpaceModifier(
            Self.trap,
            strength: 1,
            held: true,
            fadeSeconds: 1
        ))
        adapter.removeImageSpaceModifier(Self.trap, fadeSeconds: 1)
    }
}
