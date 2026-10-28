// Which perch a dragon in the perch stage of a fight lands on. The distance and the angle
// are the game's `fCombatLandingSearchDistance` and `fCombatPerchMaxTargetAngle`; the
// nearest-first order is OpenSky's. See docs/engine/dragon-flight.md#perches.

import Foundation
import simd

nonisolated public enum DragonPerchRules {
    /// The perch closest to the target among those within the search distance of it whose
    /// facing points at the target within the perch angle. Nil when none fits.
    public static func choose(
        _ perches: [DragonPerch], target: SIMD3<Float>, settings: DragonFlightSettings
    ) -> DragonPerch? {
        var best: (perch: DragonPerch, distance: Float)?
        for perch in perches {
            let offset = SIMD2(target.x - perch.feet.x, target.y - perch.feet.y)
            let distance = simd_length(offset)
            guard
                distance <= settings.perchSearchDistance,
                facingError(of: perch, toward: offset) <= settings.perchMaxTargetAngle,
                distance < best?.distance ?? .infinity
            else { continue }
            best = (perch, distance)
        }
        return best?.perch
    }

    /// The perch closest to `point` within the search distance, whatever it faces.
    public static func nearest(
        _ perches: [DragonPerch], to point: SIMD3<Float>, settings: DragonFlightSettings
    ) -> DragonPerch? {
        perches
            .map { ($0, simd_distance(SIMD2($0.feet.x, $0.feet.y), SIMD2(point.x, point.y))) }
            .filter { $0.1 <= settings.perchSearchDistance }
            .min { $0.1 < $1.1 }?.0
    }

    /// The angle between the perch's facing and the direction to the target, radians.
    static func facingError(of perch: DragonPerch, toward offset: SIMD2<Float>) -> Float {
        guard simd_length(offset) > 1 else { return 0 }
        return abs(remainder(atan2(offset.y, offset.x) - perch.yaw, 2 * Float.pi))
    }
}
