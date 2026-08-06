// Clean engine values for M4's repeatable real-install acceptance route.
// Coordinates/FormIDs identify observed records only; no game payload lives
// in the repository.

import simd

nonisolated enum WalkPathRoute {
    static let startCell = CellCoordinate(x: 6, y: -2)
    static let farmCell = CellCoordinate(x: 7, y: -3)
    static let farmDoor = FormID(0x0001_633D)
    static let interiorDoor = FormID(0x0001_63A8)
    static let farmInterior = FormID(0x0001_6204)
    static let exteriorReturn = SIMD2<Float>(31233.666, -9784.47)

    /// Road-biased route from M2 target cell to farm's exterior stair approach.
    static let exteriorWaypoints: [SIMD2<Float>] = [
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

    static let waypointTolerance: Float = 40
    static let interiorCrossingDistance: Float = 192
    static let minimumExteriorStepGain: Float = 16
    static let maximumWaypointFrames = 600
    static let maximumTransitionFrames = 1800

    static func yaw(from position: SIMD2<Float>, to target: SIMD2<Float>) -> Float {
        let delta = target - position
        return atan2f(delta.y, delta.x)
    }

    static func interiorTarget(
        from position: SIMD2<Float>,
        yaw: Float
    ) -> SIMD2<Float> {
        position + SIMD2(cosf(yaw), sinf(yaw)) * interiorCrossingDistance
    }
}
