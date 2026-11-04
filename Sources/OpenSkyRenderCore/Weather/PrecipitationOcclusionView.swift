// The top-down depth view behind the game's `bUsePrecipitationOcclusion`: it keeps the
// highest surface over each spot near the camera, so rain below a roof can be hidden.

import simd

nonisolated public enum PrecipitationOcclusionView {
    /// Half the side of the square the view covers; rain spawns well inside it.
    public static let halfSize: Float = 2048
    public static let resolution = 1024
    /// The view's top above the camera and its bottom below it.
    public static let reachAbove: Float = 6000
    public static let reachBelow: Float = 4000

    /// World to the view: x and y to clip space, z to depth 0 at the top, 1 at the
    /// bottom. The centre snaps to whole texels, so roofs do not shimmer as the camera moves.
    public static func matrix(camera: SIMD3<Float>) -> float4x4 {
        let texel = 2 * halfSize / Float(resolution)
        let centre = (SIMD2(camera.x, camera.y) / texel).rounded(.toNearestOrEven) * texel
        let top = camera.z + reachAbove
        let range = reachAbove + reachBelow
        return float4x4(columns: (
            SIMD4(1 / halfSize, 0, 0, 0),
            SIMD4(0, 1 / halfSize, 0, 0),
            SIMD4(0, 0, -1 / range, 0),
            SIMD4(-centre.x / halfSize, -centre.y / halfSize, top / range, 1)
        ))
    }
}
