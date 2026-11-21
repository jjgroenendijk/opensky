// The soft auto-aim of the player's projectiles: one target picked each frame inside a
// small screen window, and a launch direction turned a little toward it.
// docs/engine/combat-assist.md#projectile-auto-aim.

import Foundation
public import OpenSkyFormatsESM
import simd

/// One actor the auto-aim may pick, with the centre and the top of its bounds.
nonisolated public struct ProjectileAimCandidate: Equatable, Sendable {
    public let key: ReferenceKey
    public let centre: SIMD3<Float>
    public let top: SIMD3<Float>

    public init(key: ReferenceKey, centre: SIMD3<Float>, top: SIMD3<Float>) {
        self.key = key
        self.centre = centre
        self.top = top
    }
}

/// The target picked for one shot, and whether a spell may turn the whole 90 degrees.
nonisolated public struct ProjectileAimPick: Equatable, Sendable {
    public let target: ProjectileAimCandidate
    /// The player's right hand is empty or holds a melee weapon.
    public let rightHandIsFree: Bool

    public init(target: ProjectileAimCandidate, rightHandIsFree: Bool) {
        self.target = target
        self.rightHandIsFree = rightHandIsFree
    }
}

nonisolated public enum ProjectileAutoAim {
    /// A candidate farther away is not picked.
    public static let range: Float = 1800
    /// The window's half-width around the crosshair, as a part of the screen.
    public static let windowHalfWidth: Float = 6 * 0.005
    /// The largest turn in degrees, by case.
    public static let spellTurn: Float = 90
    public static let thirdPersonTurn: Float = 2
    public static let firstPersonTurn: Float = 1

    /// Where `point` shows on screen, as parts of the screen height from the
    /// crosshair. Nil for a point behind the camera.
    public static func screenOffset(
        of point: SIMD3<Float>, from origin: SIMD3<Float>, forward: SIMD3<Float>,
        fovYRadians: Float
    ) -> SIMD2<Float>? {
        let offset = point - origin
        let depth = simd_dot(offset, forward)
        let scale = tan(fovYRadians / 2)
        guard depth > 0, scale > 0, simd_length(forward) > 0 else { return nil }
        var right = simd_cross(forward, SIMD3<Float>(0, 0, 1))
        if simd_length(right) < 1e-4 {
            right = SIMD3(1, 0, 0)
        }
        right = simd_normalize(right)
        let up = simd_cross(right, forward)
        return SIMD2(simd_dot(offset, right), simd_dot(offset, up)) / (depth * scale * 2)
    }

    /// The candidate closest to the crosshair, by the sum of its screen offsets, among
    /// those in range whose centre and top both lie in the window.
    public static func pick(
        _ candidates: [ProjectileAimCandidate], from origin: SIMD3<Float>,
        forward: SIMD3<Float>, fovYRadians: Float
    ) -> ProjectileAimCandidate? {
        var best: (candidate: ProjectileAimCandidate, score: Float)?
        for candidate in candidates where simd_distance(candidate.centre, origin) <= range {
            guard
                let centre = screenOffset(
                    of: candidate.centre, from: origin, forward: forward, fovYRadians: fovYRadians
                ),
                let top = screenOffset(
                    of: candidate.top, from: origin, forward: forward, fovYRadians: fovYRadians
                ),
                simd_reduce_max(simd_abs(centre)) <= windowHalfWidth,
                simd_reduce_max(simd_abs(top)) <= windowHalfWidth
            else { continue }
            let score = abs(centre.x) + abs(centre.y)
            if best.map({ score < $0.score }) ?? true {
                best = (candidate, score)
            }
        }
        return best?.candidate
    }

    /// 90 degrees for a spell with the right hand empty or holding a melee weapon,
    /// else 2 in third person and 1 in first person.
    public static func largestTurn(spellWithFreeAim: Bool, firstPerson: Bool) -> Float {
        if spellWithFreeAim {
            return spellTurn
        }
        return firstPerson ? firstPersonTurn : thirdPersonTurn
    }

    /// `direction` turned toward `target` by at most `degrees`.
    public static func turned(
        _ direction: SIMD3<Float>, toward target: SIMD3<Float>, atMost degrees: Float
    ) -> SIMD3<Float> {
        guard simd_length(direction) > 0, simd_length(target) > 0 else { return direction }
        let from = simd_normalize(direction)
        let goal = simd_normalize(target)
        let angle = acos(min(1, max(-1, simd_dot(from, goal))))
        let limit = degrees * .pi / 180
        guard angle > limit else { return goal }
        guard angle > 1e-5 else { return from }
        let part = limit / angle
        let turned = from * sin((1 - part) * angle) + goal * sin(part * angle)
        return simd_normalize(turned)
    }
}
