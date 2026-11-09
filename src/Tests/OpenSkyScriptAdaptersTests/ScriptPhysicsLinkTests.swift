// `AddBallAndSocket` links two bodies by what each one is: a ragdoll, a loose body, or
// a still reference that can only hold a pin.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
@testable import OpenSkyScriptAdapters
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct ScriptPhysicsLinkTests {
    private let host = ScriptHost()
    private let ragdolls = FakeRagdollRuntimePort()
    private var physics: ScriptPhysicsBindingsAdapter {
        ScriptWorldAdapter(game: host, stage: nil).physicsBindings
    }

    private static let first = PhysicsLinkEnd(reference: .generated(1), node: "NPC Head")
    private static let second = PhysicsLinkEnd(reference: .generated(2), node: "NPC Spine")

    init() {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        host.fakeRagdoll.runtime = ragdolls
    }

    @Test func withoutRagdollsNothingLinks() {
        host.fakeRagdoll.runtime = nil
        #expect(physics.addBallAndSocket(Self.first, Self.second) == .returned(.boolean(false)))
    }

    @Test func twoStillReferencesDoNotLink() {
        #expect(physics.addBallAndSocket(Self.first, Self.second) == .returned(.boolean(false)))
        #expect(ragdolls.addLinkCalls.isEmpty)
    }

    @Test func twoRagdollsLinkInTheRagdollWorld() {
        host.fakeActorWorld.actorValueHolderResult = .player
        ragdolls.ragdollsForConstraintResult = true
        ragdolls.addLinkResult = true
        #expect(physics.addBallAndSocket(Self.first, Self.second) == .returned(.boolean(true)))
        #expect(ragdolls.addLinkCalls.count == 1)
    }

    @Test func anActorWithoutARagdollDoesNotLink() {
        host.fakeActorWorld.actorValueHolderResult = .player
        #expect(physics.addBallAndSocket(Self.first, Self.second) == .returned(.boolean(false)))
    }

    @Test func removingAConstraintAsksBothWorlds() {
        ragdolls.removeConstraintsResult = true
        #expect(physics.removeConstraints(Self.first, Self.second))
        #expect(ragdolls.removeConstraintsCalls.count == 1)
    }

    @Test func withoutLooseBodiesNothingIsPushed() {
        physics.publishTranslations([:], moves: [:])
        #expect(host.fakeStreamer.referenceEntryKeyCalls.isEmpty)
    }
}
