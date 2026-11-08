// Nine-slice scaling for one shape inside a sprite with a DefineScalingGrid: the
// corners keep their authored size, the edges stretch along one axis, and the
// centre takes the rest. The SWF vertex shader runs the same `remap`.
// Rules: docs/formats/swf.md, "Movie attributes".

import Foundation
import simd

/// The grid of one shape draw, in the shape's own twips.
nonisolated public struct SWFSceneScalingGrid: Equatable, Sendable {
    /// The centre rectangle: min x, min y, max x, max y.
    public let grid: SIMD4<Float>
    /// The sprite's bounds, which the corners stay anchored to.
    public let bounds: SIMD4<Float>
    /// The sprite's scale on each axis, the amount the corners undo.
    public let scale: SIMD2<Float>

    public init(grid: SIMD4<Float>, bounds: SIMD4<Float>, scale: SIMD2<Float>) {
        self.grid = grid
        self.bounds = bounds
        self.scale = scale
    }

    /// The grid for a shape placed in the sprite with `childMatrix`. Nil when
    /// the child is rotated or skewed, or the sprite has no size: Flash scales
    /// those normally too.
    public static func make(
        splitter: SWFRect,
        spriteBounds: SWFBoundsBox,
        spriteTransform: SWFTransform,
        childMatrix: SWFMatrix
    ) -> SWFSceneScalingGrid? {
        let child = SWFTransform(matrix: childMatrix)
        guard
            !spriteBounds.isEmpty, child.rotateSkew0 == 0, child.rotateSkew1 == 0,
            child.scaleX != 0, child.scaleY != 0
        else { return nil }
        let scale = SIMD2(
            (spriteTransform.scaleX * spriteTransform.scaleX
                + spriteTransform.rotateSkew0 * spriteTransform.rotateSkew0).squareRoot(),
            (spriteTransform.rotateSkew1 * spriteTransform.rotateSkew1
                + spriteTransform.scaleY * spriteTransform.scaleY).squareRoot()
        )
        guard scale.x > 0, scale.y > 0 else { return nil }
        let origin = SIMD2(child.translateX, child.translateY)
        let factor = SIMD2(child.scaleX, child.scaleY)
        func local(_ minimum: SIMD2<Float>, _ maximum: SIMD2<Float>) -> SIMD4<Float> {
            let first = (minimum - origin) / factor
            let second = (maximum - origin) / factor
            let low = simd_min(first, second)
            let high = simd_max(first, second)
            return SIMD4(low.x, low.y, high.x, high.y)
        }
        return SWFSceneScalingGrid(
            grid: local(
                SIMD2(Float(splitter.xMin), Float(splitter.yMin)),
                SIMD2(Float(splitter.xMax), Float(splitter.yMax))
            ),
            bounds: local(
                SIMD2(spriteBounds.minX, spriteBounds.minY),
                SIMD2(spriteBounds.maxX, spriteBounds.maxY)
            ),
            scale: scale
        )
    }

    /// Where the scaling grid moves a shape-local point.
    public func remap(_ point: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            Self.remap(
                point.x, span: SIMD2(bounds.x, bounds.z), grid: SIMD2(grid.x, grid.z),
                scale: scale.x
            ),
            Self.remap(
                point.y, span: SIMD2(bounds.y, bounds.w), grid: SIMD2(grid.y, grid.w),
                scale: scale.y
            )
        )
    }

    /// One axis. A sprite drawn smaller than its two corners scales normally.
    /// `span` and `grid` are each a low and a high edge.
    static func remap(
        _ value: Float, span: SIMD2<Float>, grid: SIMD2<Float>, scale: Float
    ) -> Float {
        let (low, high, gridLow, gridHigh) = (span.x, span.y, grid.x, grid.y)
        let lead = gridLow - low
        let trail = high - gridHigh
        guard
            gridHigh > gridLow, lead >= 0, trail >= 0,
            scale * (high - low) > lead + trail
        else { return value }
        if value < gridLow {
            return low + (value - low) / scale
        }
        if value > gridHigh {
            return high - (high - value) / scale
        }
        let centreLow = low + lead / scale
        let centreHigh = high - trail / scale
        return centreLow + (value - gridLow) * (centreHigh - centreLow) / (gridHigh - gridLow)
    }
}
