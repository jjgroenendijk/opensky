// The depth view behind the game's `bUsePrecipitationOcclusion`: it looks along the
// direction the rain falls and keeps the highest surface over each spot near the camera,
// so rain below a roof can be hidden.

public import simd

nonisolated public enum PrecipitationOcclusionView {
    /// Half the side of the square the view covers; rain spawns well inside it.
    public static let halfSize: Float = 2048
    /// The centre moves in steps of this many units, so roofs do not shimmer.
    public static let snap: Float = 32
    /// The view's top above the camera and its bottom below it.
    public static let reachAbove: Float = 6000
    public static let reachBelow: Float = 4000

    /// The steepest slant the view takes: one unit across for each unit down.
    public static let maximumSlant: Float = 1

    /// World to the view: a point slides along `fall` to the camera's height, then x and y
    /// go to clip space; z goes to depth 0 at the top, 1 at the bottom.
    public static func matrix(camera: SIMD3<Float>, fall: SIMD3<Float> = SIMD3(0, 0, -1))
        -> float4x4
    {
        let centre = (SIMD2(camera.x, camera.y) / snap).rounded(.toNearestOrEven) * snap
        let top = camera.z + reachAbove
        let range = reachAbove + reachBelow
        let shear = slant(of: fall)
        let across = shear / halfSize
        let offset = (-centre - shear * camera.z) / halfSize
        return float4x4(columns: (
            SIMD4(1 / halfSize, 0, 0, 0),
            SIMD4(0, 1 / halfSize, 0, 0),
            SIMD4(across.x, across.y, -1 / range, 0),
            SIMD4(offset.x, offset.y, top / range, 1)
        ))
    }

    /// Units across per unit down along `fall`; zero for a fall that is not downward.
    public static func slant(of fall: SIMD3<Float>) -> SIMD2<Float> {
        guard fall.z < 0, fall.x.isFinite, fall.y.isFinite else { return .zero }
        let slant = SIMD2(fall.x, fall.y) / -fall.z
        let length = simd_length(slant)
        return length > maximumSlant ? slant * (maximumSlant / length) : slant
    }
}
