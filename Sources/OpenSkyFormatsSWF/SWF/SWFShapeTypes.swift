// Shape style values: colors, MATRIX, gradients, fill styles, and line styles,
// separate from the bit packing in SWFShapeParser. Spec: SWF v19 chapters 1,
// 6, and 7.

import Foundation

nonisolated public enum SWFShapeError: Error, Equatable, Sendable {
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
nonisolated public struct SWFColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
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
nonisolated public struct SWFMatrix: Equatable, Sendable {
    public var scaleX: Float = 1
    public var scaleY: Float = 1
    public var rotateSkew0: Float = 0
    public var rotateSkew1: Float = 0
    public var translateX: Int32 = 0
    public var translateY: Int32 = 0

    public static let identity = SWFMatrix()
}

/// One gradient control point (GRADRECORD): position 0-255 along the ramp
/// plus its color.
nonisolated public struct SWFGradientRecord: Equatable, Sendable {
    public let ratio: UInt8
    public let color: SWFColor
}

/// GRADIENT / FOCALGRADIENT contents. `focalPoint` is non-nil only for the
/// focal radial fill type (0x13), decoded from FIXED8 (-1.0 ... 1.0).
nonisolated public struct SWFGradient: Equatable, Sendable {
    public enum SpreadMode: UInt8, Sendable {
        case pad = 0
        case reflect = 1
        case repeating = 2
        case reserved = 3
    }

    public enum InterpolationMode: UInt8, Sendable {
        case normalRGB = 0
        case linearRGB = 1
        case reserved2 = 2
        case reserved3 = 3
    }

    public let spreadMode: SpreadMode
    public let interpolationMode: InterpolationMode
    public let records: [SWFGradientRecord]
    public let focalPoint: Float?
}

/// One FILLSTYLE. Gradient and bitmap fills carry the matrix mapping their
/// source space onto shape twips (gradient square, or bitmap pixel grid).
nonisolated public enum SWFFillStyle: Equatable, Sendable {
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
nonisolated public struct SWFLineStyle: Equatable, Sendable {
    public enum CapStyle: UInt8, Sendable {
        case round = 0
        case none = 1
        case square = 2
    }

    public enum JoinStyle: Equatable, Sendable {
        case round
        case bevel
        /// Miter limit factor decoded from 8.8 fixed point.
        case miter(limitFactor: Float)
    }

    public var width: UInt16
    /// Line color; ignored when `fill` is set (LINESTYLE2 HasFillFlag).
    public var color: SWFColor
    /// LINESTYLE2 stroke fill, replacing `color` when present.
    public var fill: SWFFillStyle?
    public var startCap: CapStyle = .round
    public var endCap: CapStyle = .round
    public var join: JoinStyle = .round
    public var noHScale = false
    public var noVScale = false
    public var pixelHinting = false
    public var noClose = false

    /// LINESTYLE shorthand; LINESTYLE2 parsing mutates the remaining members.
    public init(width: UInt16, color: SWFColor) {
        self.width = width
        self.color = color
    }
}
