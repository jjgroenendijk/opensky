// Float 2x3 affine transform used by the display-list renderer: SWF MATRIX
// records concatenate through it (place -> sprite -> movie), and the
// movie-to-viewport and pixel-to-NDC mappings fold in so one transform maps a
// character's local twips straight to clip space. Field names follow the
// spec's MATRIX field names so the algebra stays checkable against it.
//
// Reference for the MATRIX semantics: Adobe SWF File Format Specification,
// version 19, chapter 1 "MATRIX record" (p. 23):
// `x' = x * ScaleX + y * RotateSkew1 + TranslateX`,
// `y' = x * RotateSkew0 + y * ScaleY + TranslateY`.

import Foundation
import simd

/// Affine map `out.x = scaleX*x + rotateSkew1*y + translateX`,
/// `out.y = rotateSkew0*x + scaleY*y + translateY`.
nonisolated struct SWFTransform: Equatable {
    var scaleX: Float = 1
    var rotateSkew0: Float = 0
    var rotateSkew1: Float = 0
    var scaleY: Float = 1
    var translateX: Float = 0
    var translateY: Float = 0

    static let identity = SWFTransform(scaleX: 1, scaleY: 1)

    /// Lifts a decoded MATRIX record (translation in twips).
    init(matrix: SWFMatrix) {
        scaleX = matrix.scaleX
        rotateSkew0 = matrix.rotateSkew0
        rotateSkew1 = matrix.rotateSkew1
        scaleY = matrix.scaleY
        translateX = Float(matrix.translateX)
        translateY = Float(matrix.translateY)
    }

    init(
        scaleX: Float,
        rotateSkew0: Float,
        rotateSkew1: Float,
        scaleY: Float,
        translateX: Float,
        translateY: Float
    ) {
        (self.scaleX, self.rotateSkew0) = (scaleX, rotateSkew0)
        (self.rotateSkew1, self.scaleY) = (rotateSkew1, scaleY)
        (self.translateX, self.translateY) = (translateX, translateY)
    }

    /// Pure scale + translation.
    init(scaleX: Float, scaleY: Float, translateX: Float = 0, translateY: Float = 0) {
        self.init(
            scaleX: scaleX,
            rotateSkew0: 0,
            rotateSkew1: 0,
            scaleY: scaleY,
            translateX: translateX,
            translateY: translateY
        )
    }

    func apply(_ point: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            scaleX * point.x + rotateSkew1 * point.y + translateX,
            rotateSkew0 * point.x + scaleY * point.y + translateY
        )
    }

    /// The transform equivalent to applying `inner` first, then `self` — the
    /// order a parent timeline wraps a child placement.
    func concatenating(_ inner: SWFTransform) -> SWFTransform {
        SWFTransform(
            scaleX: scaleX * inner.scaleX + rotateSkew1 * inner.rotateSkew0,
            rotateSkew0: rotateSkew0 * inner.scaleX + scaleY * inner.rotateSkew0,
            rotateSkew1: scaleX * inner.rotateSkew1 + rotateSkew1 * inner.scaleY,
            scaleY: rotateSkew0 * inner.rotateSkew1 + scaleY * inner.scaleY,
            translateX: scaleX * inner.translateX + rotateSkew1 * inner.translateY + translateX,
            translateY: rotateSkew0 * inner.translateX + scaleY * inner.translateY + translateY
        )
    }

    /// nil when the linear part is singular (a degenerate fill matrix).
    var inverted: SWFTransform? {
        let determinant = scaleX * scaleY - rotateSkew0 * rotateSkew1
        guard determinant.isFinite, abs(determinant) > .ulpOfOne else { return nil }
        let inverse = 1 / determinant
        return SWFTransform(
            scaleX: scaleY * inverse,
            rotateSkew0: -rotateSkew0 * inverse,
            rotateSkew1: -rotateSkew1 * inverse,
            scaleY: scaleX * inverse,
            translateX: (rotateSkew1 * translateY - scaleY * translateX) * inverse,
            translateY: (rotateSkew0 * translateX - scaleX * translateY) * inverse
        )
    }

    /// Area-preserving uniform scale estimate — the factor glyph
    /// rasterization uses to pick a pixel size under this transform.
    var approximateScale: Float {
        let determinant = abs(scaleX * scaleY - rotateSkew0 * rotateSkew1)
        return determinant.isFinite ? determinant.squareRoot() : 0
    }

    /// The linear part in the order `SWFDrawUniforms` expects
    /// (ScaleX, RotateSkew0, RotateSkew1, ScaleY).
    var packedLinear: SIMD4<Float> {
        SIMD4(scaleX, rotateSkew0, rotateSkew1, scaleY)
    }

    var packedTranslation: SIMD2<Float> {
        SIMD2(translateX, translateY)
    }
}

/// Deterministic stage-to-viewport mapping: uniform scale that fits the
/// movie's FrameSize into the viewport, centered (letterboxed on mismatched
/// aspect ratios). Same movie + same viewport -> the same transform.
nonisolated enum SWFViewportMapping {
    /// Twips -> framebuffer pixels for a movie frame rendered into
    /// `viewportPixels`.
    static func twipsToPixels(
        frameSize: SWFRect,
        viewportPixels: SIMD2<Float>
    ) -> SWFTransform {
        let widthTwips = Float(frameSize.xMax - frameSize.xMin)
        let heightTwips = Float(frameSize.yMax - frameSize.yMin)
        guard
            widthTwips > 0, heightTwips > 0,
            viewportPixels.x > 0, viewportPixels.y > 0
        else {
            return .identity
        }
        let scale = min(viewportPixels.x / widthTwips, viewportPixels.y / heightTwips)
        let offsetX = (viewportPixels.x - widthTwips * scale) / 2
        let offsetY = (viewportPixels.y - heightTwips * scale) / 2
        return SWFTransform(
            scaleX: scale,
            scaleY: scale,
            translateX: offsetX - Float(frameSize.xMin) * scale,
            translateY: offsetY - Float(frameSize.yMin) * scale
        )
    }

    /// Framebuffer pixels (origin top-left, y down) -> Metal NDC.
    static func pixelsToClip(viewportPixels: SIMD2<Float>) -> SWFTransform {
        guard viewportPixels.x > 0, viewportPixels.y > 0 else { return .identity }
        return SWFTransform(
            scaleX: 2 / viewportPixels.x,
            scaleY: -2 / viewportPixels.y,
            translateX: -1,
            translateY: 1
        )
    }
}
