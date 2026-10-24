// A push on an NPC: a standing actor slides on its own capsule until the push fades
// and parks there; a walking actor takes the push on its mover.

@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
@testable import OpenSkyWorldState
import simd
import Testing

extension NPCMovementRuntimeTests {
    @Test
    func aStandingActorSlidesFromAPushAndParksWhereItStops() {
        var runtime = NPCMovementRuntime()
        var persistence: [NPCMovementPersistence] = []
        runtime.onPersist = { persistence.append($0) }
        let knocked = runtime.knock(
            Self.face(actor: actor, target: .zero),
            velocity: SIMD3(400, 0, 0),
            configuration: .synthetic
        )
        #expect(knocked)
        runtime.advance(by: 1.0 / 60, world: Self.world())
        #expect(runtime.readouts().first?.state == .knockedBack)
        for _ in 0 ..< 240 {
            runtime.advance(by: 1.0 / 60, world: Self.world())
        }

        let rest = runtime.transform(for: actor)?.position ?? .zero
        #expect(rest.x > 50)
        #expect(abs(rest.y) < 0.001)
        #expect(runtime.readouts().first?.state == .halted)
        #expect(persistence.map(\.reason) == [.halt])
        #expect(runtime.instanceDeltas()[UInt32(1)] != nil)
    }

    @Test
    func aWalkingActorTakesThePushOnItsMover() {
        var runtime = NPCMovementRuntime()
        let walked = runtime.start(Self.start(
            actor: actor,
            path: Self.path(waypoints: [SIMD3(0, 2000, 0)], target: SIMD3(0, 2000, 0))
        ))
        #expect(walked)
        runtime.knock(
            Self.face(actor: actor, target: .zero),
            velocity: SIMD3(600, 0, 0),
            configuration: .synthetic
        )
        for _ in 0 ..< 30 {
            runtime.advance(by: 1.0 / 60, world: Self.world())
        }

        #expect(runtime.activeMoverCount == 1)
        #expect((runtime.transform(for: actor)?.position.x ?? 0) > 50)
    }

    @Test
    func aRiddenActorIsNotPushed() {
        var runtime = NPCMovementRuntime()
        _ = runtime.takeRidden(Self.face(actor: actor, target: .zero))
        let knocked = runtime.knock(
            Self.face(actor: actor, target: .zero),
            velocity: SIMD3(400, 0, 0),
            configuration: .synthetic
        )
        #expect(!knocked)
    }
}
