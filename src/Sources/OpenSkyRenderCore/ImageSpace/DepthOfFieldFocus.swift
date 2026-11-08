// The game's depth of field that focuses on what the player looks at: the focus comes
// from the depth at the screen centre, and the centre counts more once the view is still
// (docs/rendering/post-effects.md#focus-on-the-view-centre).

import Foundation
import simd

nonisolated public struct DepthOfFieldFocus: Equatable, Sendable {
    /// The centre weight while the view moves, and once it has been still.
    public static let movingWeight: Float = 0.6
    public static let stillExteriorWeight: Float = 1.6
    public static let stillInteriorWeight: Float = 1.0
    /// Seconds the view stays still before the weight changes, and how long the change takes.
    public static let delay: Float = 0.5
    public static let change: Float = 1.0
    /// A turn of 2 degrees or a move of 5 units counts as moving.
    public static let turnLimit: Float = 2 * .pi / 180
    public static let moveLimit: Float = 5

    private var angles: SIMD3<Float>?
    private var position: SIMD3<Float>?
    private var stillSeconds: Float = 0
    public private(set) var centreWeight = Self.movingWeight

    public init() {}

    /// `angles` are the player's pitch, roll, and heading in radians.
    public mutating func advance(
        angles: SIMD3<Float>, position: SIMD3<Float>, interior: Bool, seconds: Float
    ) {
        let turned = self.angles.map { simd_reduce_max(abs($0 - angles)) >= Self.turnLimit } ?? true
        let moved = self.position
            .map { simd_reduce_max(abs($0 - position)) >= Self.moveLimit } ?? true
        self.angles = angles
        self.position = position
        guard !turned, !moved else {
            stillSeconds = 0
            centreWeight = Self.movingWeight
            return
        }
        stillSeconds += seconds.isFinite ? max(seconds, 0) : 0
        let share = min(max((stillSeconds - Self.delay) / Self.change, 0), 1)
        let still = interior ? Self.stillInteriorWeight : Self.stillExteriorWeight
        centreWeight = Self.movingWeight + (still - Self.movingWeight) * sin(share * .pi / 2)
    }
}
