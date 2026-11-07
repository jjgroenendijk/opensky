// The lag bone step from the game's rule: a small gap snaps shut, a gap past the
// maximum distance loses the excess at once, and zero velocity keeps the bone at rest.

@testable import OpenSkyFormatsMesh
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFLagBoneRuleTests {
    private static func at(_ position: SIMD3<Float>) -> NIFNodeTransform {
        NIFNodeTransform(
            translation: position,
            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            scale: 1
        )
    }

    private static let lag = NIFLagBone(linearVelocity: 2, linearRotation: 0, maximumDistance: 10)

    @Test func aGapInsideTheMaximumClosesTheRateTimesTheFrame() {
        let next = NIFLagBoneMotion.step(
            Self.at(.zero),
            toward: Self.at([8, 0, 0]),
            Self.lag,
            deltaTime: 0.1
        )
        // k = 2 * 0.1 = 0.2, so the bone moves 8 * 0.2.
        #expect(simd_distance(next.translation, [1.6, 0, 0]) < 1e-5)
    }

    @Test func aGapPastTheMaximumDropsTheExcessFirst() {
        let next = NIFLagBoneMotion.step(
            Self.at(.zero),
            toward: Self.at([30, 0, 0]),
            Self.lag,
            deltaTime: 0.1
        )
        // The start moves 20 to sit 10 behind, then closes 10 * 0.2.
        #expect(simd_distance(next.translation, [22, 0, 0]) < 1e-5)
    }

    @Test func aGapSmallerThanTheRateSnapsToRest() {
        let next = NIFLagBoneMotion.step(
            Self.at(.zero),
            toward: Self.at([0.1, 0, 0]),
            Self.lag,
            deltaTime: 0.1
        )
        #expect(next.translation == [0.1, 0, 0])
    }

    @Test func zeroVelocityKeepsTheBoneAtRest() {
        let still = NIFLagBone(linearVelocity: 0, linearRotation: 0, maximumDistance: 10)
        let next = NIFLagBoneMotion.step(
            Self.at(.zero),
            toward: Self.at([5, 0, 0]),
            still,
            deltaTime: 0.1
        )
        #expect(next.translation == [5, 0, 0])
    }

    @Test func theRotationTurnsItsShareOfTheWayPerSecond() {
        let turning = NIFLagBone(linearVelocity: 0, linearRotation: 5, maximumDistance: 10)
        var goal = Self.at(.zero)
        goal.rotation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        let next = NIFLagBoneMotion.step(Self.at(.zero), toward: goal, turning, deltaTime: 0.1)
        // A normalised lerp halfway between identity and a quarter turn is an eighth turn.
        #expect(abs(next.rotation.angle - .pi / 4) < 1e-4)
    }
}
