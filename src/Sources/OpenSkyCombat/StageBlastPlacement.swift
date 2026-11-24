// Where a destruction stage's explosion goes off: the centre of the reference's bounds,
// moved by a random amount within the bound radius.
// See docs/engine/papyrus-destruction.md#in-the-game.

import Foundation
import simd

nonisolated public enum StageBlastPlacement {
    /// The seed of the stream the random offsets draw from.
    public static let seed: UInt64 = 0x4445_5354

    /// `bounds.centre` is in the reference's frame; `heading` turns it clockwise, as a
    /// placement's z rotation does. `random` draws three numbers in 0 ..< 1.
    public static func position(
        origin: SIMD3<Float>, bounds: (centre: SIMD3<Float>, radius: Float), heading: Float,
        random: () -> Float
    ) -> SIMD3<Float> {
        let (centre, radius) = bounds
        let (sine, cosine) = (sin(heading), cos(heading))
        let turned = SIMD3(
            centre.x * cosine + centre.y * sine, -centre.x * sine + centre.y * cosine, centre.z
        )
        guard radius > 0, radius.isFinite else { return origin + turned }
        let yaw = random() * 2 * .pi
        let rise = random() * 2 - 1
        let flat = (1 - rise * rise).squareRoot()
        let direction = SIMD3(flat * cos(yaw), flat * sin(yaw), rise)
        return origin + turned + direction * random() * radius
    }
}
