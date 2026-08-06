// Value types for SWF shape styles: colors, the 2x3 MATRIX record, gradients,
// fill styles, and line styles. Decoupled from the on-disk bit packing, which
// lives in SWFShapeParser.
//
// Reference: Adobe SWF File Format Specification, version 19 — "RGB color
// record" / "RGBA color with alpha record" / "MATRIX record" (chapter 1,
// pp. 21-23), "Fill styles" / "Line styles" (chapter 6, pp. 121-125), and
// "Gradient structures" (chapter 7, pp. 135-136).

import Foundation

nonisolated enum SWFShapeError: Error, Equatable {
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
nonisolated struct SWFColor: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8
}

/// The 2x3 transform from the MATRIX record. Scale/rotate terms are 16.16
/// fixed point decoded to Float; translation is in twips. Maps
/// `x' = x*scaleX + y*rotateSkew1 + translateX`,
/// `y' = x*rotateSkew0 + y*scaleY + translateY` (spec chapter 1, p. 23).
nonisolated struct SWFMatrix: Equatable {
    var scaleX: Float = 1
    var scaleY: Float = 1
    var rotateSkew0: Float = 0
    var rotateSkew1: Float = 0
    var translateX: Int32 = 0
    var translateY: Int32 = 0

    static let identity = SWFMatrix()
}

/// One gradient control point (GRADRECORD): position 0-255 along the ramp
/// plus its color.
nonisolated struct SWFGradientRecord: Equatable {
    let ratio: UInt8
    let color: SWFColor
}

/// GRADIENT / FOCALGRADIENT contents. `focalPoint` is non-nil only for the
/// focal radial fill type (0x13), decoded from FIXED8 (-1.0 ... 1.0).
nonisolated struct SWFGradient: Equatable {
    enum SpreadMode: UInt8 {
        case pad = 0
        case reflect = 1
        case repeating = 2
        case reserved = 3
    }

    enum InterpolationMode: UInt8 {
        case normalRGB = 0
        case linearRGB = 1
        case reserved2 = 2
        case reserved3 = 3
    }

    let spreadMode: SpreadMode
    let interpolationMode: InterpolationMode
    let records: [SWFGradientRecord]
    let focalPoint: Float?
}

/// One FILLSTYLE. Gradient and bitmap fills carry the matrix mapping their
/// source space onto shape twips (gradient square, or bitmap pixel grid).
nonisolated enum SWFFillStyle: Equatable {
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
/// Stroke tessellation is deferred — see docs/formats/swf.md.
nonisolated struct SWFLineStyle: Equatable {
    enum CapStyle: UInt8 {
        case round = 0
        case none = 1
        case square = 2
    }

    enum JoinStyle: Equatable {
        case round
        case bevel
        /// Miter limit factor decoded from 8.8 fixed point.
        case miter(limitFactor: Float)
    }

    var width: UInt16
    /// Line color; ignored when `fill` is set (LINESTYLE2 HasFillFlag).
    var color: SWFColor
    /// LINESTYLE2 stroke fill, replacing `color` when present.
    var fill: SWFFillStyle?
    var startCap: CapStyle = .round
    var endCap: CapStyle = .round
    var join: JoinStyle = .round
    var noHScale = false
    var noVScale = false
    var pixelHinting = false
    var noClose = false

    /// LINESTYLE shorthand; LINESTYLE2 parsing mutates the remaining members.
    init(width: UInt16, color: SWFColor) {
        self.width = width
        self.color = color
    }
}
