// Value types for SWF shape styles: colors, the 2x3 MATRIX record, gradients,
// fill styles, and line styles. Decoupled from the on-disk bit packing, which
// lives in SWFShapeParser.
//
// Reference: Adobe SWF File Format Specification, version 19 — "RGB color
// record" / "RGBA color with alpha record" / "MATRIX record" (chapter 1,
// pp. 21-23), "Fill styles" / "Line styles" (chapter 6, pp. 121-125), and
// "Gradient structures" (chapter 7, pp. 135-136).

import Foundation

nonisolated package enum SWFShapeError: Error, Equatable {
    /// Tag code is not DefineShape (2), DefineShape2 (22), DefineShape3 (32),
    /// or DefineShape4 (83).
    case unsupportedTag(UInt16)
    /// FillStyleType byte outside the values listed in the FILLSTYLE table.
    case invalidFillStyleType(UInt8)
    /// A glyph SHAPE carried a StateNewStyles flag, which only SHAPEWITHSTYLE
    /// (with its style arrays) can satisfy.
    case newStylesInGlyph
    /// A style-change record selected a style index past its style array.
    case styleIndexOutOfRange(index: Int, count: Int)
}

/// 8-bit RGBA color. RGB records (DefineShape/DefineShape2) parse with
/// `alpha` fixed at 255 per the spec's RGB record.
nonisolated package struct SWFColor: Equatable {
    package var red: UInt8
    package var green: UInt8
    package var blue: UInt8
    package var alpha: UInt8

    package init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// The 2x3 transform from the MATRIX record. Scale/rotate terms are 16.16
/// fixed point decoded to Float; translation is in twips. Maps
/// `x' = x*scaleX + y*rotateSkew1 + translateX`,
/// `y' = x*rotateSkew0 + y*scaleY + translateY` (spec chapter 1, p. 23).
nonisolated package struct SWFMatrix: Equatable {
    package var scaleX: Float = 1
    package var scaleY: Float = 1
    package var rotateSkew0: Float = 0
    package var rotateSkew1: Float = 0
    package var translateX: Int32 = 0
    package var translateY: Int32 = 0

    package static let identity = SWFMatrix()
}

/// One gradient control point (GRADRECORD): position 0-255 along the ramp
/// plus its color.
nonisolated package struct SWFGradientRecord: Equatable {
    package let ratio: UInt8
    package let color: SWFColor
}

/// GRADIENT / FOCALGRADIENT contents. `focalPoint` is non-nil only for the
/// focal radial fill type (0x13), decoded from FIXED8 (-1.0 ... 1.0).
nonisolated package struct SWFGradient: Equatable {
    package enum SpreadMode: UInt8 {
        case pad = 0
        case reflect = 1
        case repeating = 2
        case reserved = 3
    }

    package enum InterpolationMode: UInt8 {
        case normalRGB = 0
        case linearRGB = 1
        case reserved2 = 2
        case reserved3 = 3
    }

    package let spreadMode: SpreadMode
    package let interpolationMode: InterpolationMode
    package let records: [SWFGradientRecord]
    package let focalPoint: Float?
}

/// One FILLSTYLE. Gradient and bitmap fills carry the matrix mapping their
/// source space onto shape twips (gradient square, or bitmap pixel grid).
nonisolated package enum SWFFillStyle: Equatable {
    case solid(SWFColor)
    case linearGradient(matrix: SWFMatrix, gradient: SWFGradient)
    case radialGradient(matrix: SWFMatrix, gradient: SWFGradient)
    case focalRadialGradient(matrix: SWFMatrix, gradient: SWFGradient)
    /// `tiled` distinguishes repeating (0x40/0x42) from clipped (0x41/0x43);
    /// `smoothed` distinguishes 0x40/0x41 from the non-smoothed 0x42/0x43.
    case bitmap(characterId: UInt16, matrix: SWFMatrix, tiled: Bool, smoothed: Bool)
}

/// One LINESTYLE or LINESTYLE2 entry. LINESTYLE (DefineShape-DefineShape3)
/// fills only `width` and `color`; the remaining members keep the spec
/// defaults for pre-SWF8 lines (round caps and joins, closed, scaling).
/// Stroke tessellation is deferred — see docs/formats/swf-shapes.md.
nonisolated package struct SWFLineStyle: Equatable {
    package enum CapStyle: UInt8 {
        case round = 0
        case none = 1
        case square = 2
    }

    package enum JoinStyle: Equatable {
        case round
        case bevel
        /// Miter limit factor decoded from 8.8 fixed point.
        case miter(limitFactor: Float)
    }

    package var width: UInt16
    /// Line color; ignored when `fill` is set (LINESTYLE2 HasFillFlag).
    package var color: SWFColor
    /// LINESTYLE2 stroke fill, replacing `color` when present.
    package var fill: SWFFillStyle?
    package var startCap: CapStyle = .round
    package var endCap: CapStyle = .round
    package var join: JoinStyle = .round
    package var noHScale = false
    package var noVScale = false
    package var pixelHinting = false
    package var noClose = false

    /// LINESTYLE shorthand; LINESTYLE2 parsing mutates the remaining members.
    package init(width: UInt16, color: SWFColor) {
        self.width = width
        self.color = color
    }
}
