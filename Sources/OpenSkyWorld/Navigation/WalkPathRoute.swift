// Engine values for the repeatable real-install walk route. Coordinates and FormIDs only
// identify observed records; no game payload is stored.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

nonisolated public enum WalkPathRoute: Sendable {
    public static let startCell = CellCoordinate(x: 6, y: -2)
    public static let farmCell = CellCoordinate(x: 7, y: -3)
    public static let farmDoor = FormID(0x0001_633D)
    public static let interiorDoor = FormID(0x0001_63A8)
    public static let farmInterior = FormID(0x0001_6204)
    public static let exteriorReturn = SIMD2<Float>(31233.666, -9784.47)

    /// Road-biased route from the first-render cell to the farm's exterior stair approach.
    public static let exteriorWaypoints: [SIMD2<Float>] = [
        SIMD2(28600, -7600),
        SIMD2(29400, -7600),
        SIMD2(30000, -8400),
        SIMD2(30600, -9200),
        SIMD2(30200, -9700),
        SIMD2(30200, -9900),
        SIMD2(30500, -10000),
        SIMD2(30900, -10100),
        SIMD2(31350, -10100),
        SIMD2(31400, -9900),
        exteriorReturn
    ]

    public static let waypointTolerance: Float = 40
    public static let interiorCrossingDistance: Float = 192
    public static let interiorOpeningLateralOffset: Float = 240
    public static let interiorOpeningApproachDistance: Float = 80
    public static let interiorOpeningExitDistance: Float = 176
    public static let minimumExteriorStepGain: Float = 16
    public static let maximumWaypointFrames = 600
    public static let maximumTransitionFrames = 1800

    public static func yaw(from position: SIMD2<Float>, to target: SIMD2<Float>) -> Float {
        let delta = target - position
        return atan2f(delta.y, delta.x)
    }

    public static func interiorTarget(
        from position: SIMD2<Float>,
        yaw: Float
    ) -> SIMD2<Float> {
        position + SIMD2(cosf(yaw), sinf(yaw)) * interiorCrossingDistance
    }

    public static func interiorWaypoints(
        from position: SIMD2<Float>,
        yaw: Float
    ) -> [SIMD2<Float>] {
        let forward = SIMD2(cosf(yaw), sinf(yaw))
        let left = SIMD2(-forward.y, forward.x)
        return [
            position
                + forward * interiorOpeningApproachDistance
                + left * interiorOpeningLateralOffset,
            position
                + forward * interiorOpeningExitDistance
                + left * interiorOpeningLateralOffset
        ]
    }
}
