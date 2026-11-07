// A graph's root motion moves an actor only while the graph is animation-driven.

@testable import OpenSkyActorPresentation
import OpenSkyBehavior
import simd
import Testing

struct ActorGraphRootMotionTests {
    private static func motion(forward: Float, turn: Float = 0) -> BehaviorRootMotion {
        BehaviorRootMotion(
            translation: SIMD3(0, forward, 0),
            rotation: simd_quatf(angle: turn, axis: SIMD3(0, 0, 1)),
            isExtracted: true
        )
    }

    @Test func aMotionDrivenGraphLeavesTheActorToItsMover() {
        let step = ActorGraphRootMotion.step(
            Self.motion(forward: 10), variables: { _ in false }, heading: 0, scale: 1
        )
        #expect(step == nil)
    }

    @Test func anAnimationDrivenGraphMovesAlongTheHeadingAndTurns() throws {
        let step = try #require(ActorGraphRootMotion.step(
            Self.motion(forward: 10, turn: .pi / 2),
            variables: { $0 == ActorGraphRootMotion.animationDriven },
            heading: .pi / 2, scale: 2
        ))
        #expect(simd_distance(step.displacement, SIMD2(20, 0)) < 0.001)
        #expect(abs(step.headingTurn + .pi / 2) < 0.001)
    }

    @Test func allowRotationKeepsTheHeading() throws {
        let step = try #require(ActorGraphRootMotion.step(
            Self.motion(forward: 10, turn: 1), variables: { _ in true }, heading: 0, scale: 1
        ))
        #expect(step.headingTurn == 0)
        #expect(simd_distance(step.displacement, SIMD2(0, 10)) < 0.001)
    }
}
