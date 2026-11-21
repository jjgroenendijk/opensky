// Glyphs and inline pictures rasterize upright at the on-screen pixel size, so a quad is laid
// out in that upright space and its corners then follow the text's rotation, skew, and uneven
// scale. The field's bottom edge cuts the quad in the same upright space, as Flash does.

import OpenSkyFormatsSWF
import OpenSkyShaderTypes
import simd

/// One textured quad of the SWF glyph ring, its corners in framebuffer pixels.
nonisolated struct SWFTextQuad: Equatable, Sendable {
    var topLeft: SIMD2<Float>
    var topRight: SIMD2<Float>
    var bottomLeft: SIMD2<Float>
    var bottomRight: SIMD2<Float>
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>

    /// The upright shape of `textToPixels`: its linear part divided by its uniform scale.
    /// The identity for a transform that only moves and scales evenly.
    static func shape(of textToPixels: SWFTransform) -> SWFTransform {
        let scale = textToPixels.approximateScale
        guard scale > 0 else { return .identity }
        return SWFTransform(
            scaleX: textToPixels.scaleX / scale,
            rotateSkew0: textToPixels.rotateSkew0 / scale,
            rotateSkew1: textToPixels.rotateSkew1 / scale,
            scaleY: textToPixels.scaleY / scale,
            translateX: 0,
            translateY: 0
        )
    }

    /// A quad from `localMin` to `localMax`, upright pixel offsets from `origin`, mapped
    /// through `shape`. `localBottom`, in the same offsets, cuts the quad and its UVs; nil
    /// when nothing of it stays above the cut.
    init?(
        origin: SIMD2<Float>,
        shape: SWFTransform,
        localMin: SIMD2<Float>,
        localMax: SIMD2<Float>,
        localBottom: Float?,
        uvMin: SIMD2<Float>,
        uvMax: SIMD2<Float>
    ) {
        var bottom = localMax.y
        var uvBottom = uvMax.y
        if let localBottom, localBottom < localMax.y {
            guard localBottom > localMin.y else { return nil }
            let kept = (localBottom - localMin.y) / (localMax.y - localMin.y)
            uvBottom = uvMin.y + (uvMax.y - uvMin.y) * kept
            bottom = localBottom
        }
        let place = { (offset: SIMD2<Float>) in origin + shape.apply(offset) }
        topLeft = place(localMin)
        topRight = place(SIMD2(localMax.x, localMin.y))
        bottomLeft = place(SIMD2(localMin.x, bottom))
        bottomRight = place(SIMD2(localMax.x, bottom))
        self.uvMin = uvMin
        self.uvMax = SIMD2(uvMax.x, uvBottom)
    }

    /// Pixel position -> 0...1 of the quad before the cut, for a bitmap fill; nil when the
    /// quad has no area.
    static func pixelsToUnit(
        origin: SIMD2<Float>,
        shape: SWFTransform,
        localMin: SIMD2<Float>,
        localSize: SIMD2<Float>
    ) -> SWFTransform? {
        let unitToLocal = SWFTransform(
            scaleX: localSize.x, scaleY: localSize.y,
            translateX: localMin.x, translateY: localMin.y
        )
        var unitToPixels = shape.concatenating(unitToLocal)
        unitToPixels.translateX += origin.x
        unitToPixels.translateY += origin.y
        return unitToPixels.inverted
    }

    /// Two triangles, in the ring's winding.
    var vertices: [SWFVertex] {
        let topLeft = SWFVertex(position: topLeft, uv: uvMin)
        let topRight = SWFVertex(position: topRight, uv: SIMD2(uvMax.x, uvMin.y))
        let bottomLeft = SWFVertex(position: bottomLeft, uv: SIMD2(uvMin.x, uvMax.y))
        let bottomRight = SWFVertex(position: bottomRight, uv: uvMax)
        return [topLeft, topRight, bottomLeft, topRight, bottomRight, bottomLeft]
    }
}
