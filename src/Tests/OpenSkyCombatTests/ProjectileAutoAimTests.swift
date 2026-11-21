// The auto-aim window, the pick, and the largest turn of a launched projectile
// (docs/engine/combat-assist.md#projectile-auto-aim).

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd
import Testing

struct ProjectileAutoAimTests {
    private let forward = SIMD3<Float>(1, 0, 0)
    private let fovY: Float = 65 * .pi / 180

    private func candidate(_ id: UInt32, at centre: SIMD3<Float>) -> ProjectileAimCandidate {
        ProjectileAimCandidate(
            key: .plugin(name: "test.esm", objectID: id), centre: centre,
            top: centre + SIMD3(0, 0, 10)
        )
    }

    @Test func aPointOnTheAimRayShowsAtTheCrosshair() throws {
        let offset = try #require(ProjectileAutoAim.screenOffset(
            of: SIMD3(500, 0, 0), from: .zero, forward: forward, fovYRadians: fovY
        ))
        #expect(offset == .zero)
        #expect(ProjectileAutoAim.screenOffset(
            of: SIMD3(-500, 0, 0), from: .zero, forward: forward, fovYRadians: fovY
        ) == nil)
    }

    @Test func theClosestCandidateInTheWindowIsPicked() {
        let near = candidate(1, at: SIMD3(1000, 10, 0))
        let nearer = candidate(2, at: SIMD3(1000, 2, 0))
        let outside = candidate(3, at: SIMD3(1000, 300, 0))
        let far = candidate(4, at: SIMD3(2000, 0, 0))
        let pick = ProjectileAutoAim.pick(
            [near, nearer, outside, far], from: .zero, forward: forward, fovYRadians: fovY
        )
        #expect(pick == nearer)
        #expect(ProjectileAutoAim.pick(
            [outside, far], from: .zero, forward: forward, fovYRadians: fovY
        ) == nil)
    }

    @Test func theLargestTurnDependsOnTheShotAndTheCamera() {
        #expect(ProjectileAutoAim.largestTurn(spellWithFreeAim: true, firstPerson: true) == 90)
        #expect(ProjectileAutoAim.largestTurn(spellWithFreeAim: false, firstPerson: false) == 2)
        #expect(ProjectileAutoAim.largestTurn(spellWithFreeAim: false, firstPerson: true) == 1)
    }

    /// The page's example: aimed 3 degrees off, an arrow in first person leaves 2 degrees off.
    @Test func theDirectionTurnsAtMostTheLimit() {
        let off: Float = 3 * .pi / 180
        let target = SIMD3<Float>(cos(off), sin(off), 0)
        let turned = ProjectileAutoAim.turned(forward, toward: target, atMost: 1)
        let left = acos(simd_dot(turned, target)) * 180 / .pi
        #expect(abs(left - 2) < 0.01)
        #expect(simd_distance(ProjectileAutoAim.turned(forward, toward: target, atMost: 90), target)
            < 0.0001)
        #expect(ProjectileAutoAim.turned(forward, toward: .zero, atMost: 1) == forward)
    }
}
