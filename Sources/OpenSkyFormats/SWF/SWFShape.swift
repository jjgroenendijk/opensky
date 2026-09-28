// DefineShape tag decoding: DefineShape (2), DefineShape2 (22),
// DefineShape3 (32), DefineShape4 (83). The tag body is a character id, the
// shape bounds RECT (plus edge bounds and hint flags for DefineShape4), and a
// SHAPEWITHSTYLE. Style-change records that push new style arrays are
// flattened here into single global fill/line style lists so a segment's
// style index is stable for the whole shape.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 6
// "Shapes" — "Shape tags" (pp. 131-133) and "Shape structures" (pp. 125-131).

import Foundation

/// One drawn edge produced by walking the shape records, in absolute twips
/// (move-to deltas are relative to the shape origin, so the walk yields
/// absolute positions). Style indices are 0 for "no style" or a 1-based index
/// into `SWFShapeDefinition.fillStyles` / `.lineStyles` — the same convention
/// the file uses, kept so index 0 stays the documented "not filled" marker.
nonisolated public struct SWFShapeSegment: Equatable, Sendable {
    public enum Edge: Equatable, Sendable {
        case line(toX: Int32, toY: Int32)
        /// Quadratic Bezier: control point then end anchor (spec
        /// CurvedEdgeRecord, p. 130).
        case quadratic(controlX: Int32, controlY: Int32, toX: Int32, toY: Int32)
    }

    public let fromX: Int32
    public let fromY: Int32
    public let edge: Edge
    /// Fill on the left of the travel direction (spec "FillStyle0 and
    /// FillStyle1", p. 128).
    public let fillStyle0: Int
    /// Fill on the right of the travel direction.
    public let fillStyle1: Int
    public let lineStyle: Int

    public var endPoint: (x: Int32, y: Int32) {
        switch edge {
        case let .line(toX, toY): (toX, toY)
        case let .quadratic(_, _, toX, toY): (toX, toY)
        }
    }
}

/// A decoded DefineShape character: styles plus the flat edge list.
nonisolated public struct SWFShapeDefinition: Equatable, Sendable {
    /// Tag codes this parser accepts, in spec order.
    public static let tagCodes: Set<UInt16> = [2, 22, 32, 83]

    public let characterId: UInt16
    /// Shape bounds in twips (strokes included).
    public let bounds: SWFRect
    /// DefineShape4 only: bounds excluding strokes.
    public let edgeBounds: SWFRect?
    /// DefineShape4 UsesFillWindingRule (SWF 10+). False selects the default
    /// even-odd fill rule.
    public let usesFillWindingRule: Bool
    /// Flattened across StateNewStyles generations; segments index into this
    /// 1-based (0 = unfilled).
    public let fillStyles: [SWFFillStyle]
    public let lineStyles: [SWFLineStyle]
    public let segments: [SWFShapeSegment]

    /// Decodes a DefineShape/2/3/4 tag body.
    public static func parse(tag: SWFTag) throws -> SWFShapeDefinition {
        guard let version = SWFShapeVersion(tagCode: tag.code) else {
            throw SWFShapeError.unsupportedTag(tag.code)
        }
        var bits = SWFBitReader(tag.body)
        let characterId = try bits.readAlignedUInt16()
        let bounds = try SWFShapeParser.parseRect(&bits)
        var edgeBounds: SWFRect?
        var windingRule = false
        if version == .shape4 {
            edgeBounds = try SWFShapeParser.parseRect(&bits)
            bits.align()
            _ = try bits.readUB(5) // Reserved, must be 0
            windingRule = try bits.readUB(1) == 1
            _ = try bits.readUB(2) // UsesNonScalingStrokes, UsesScalingStrokes
        }
        let parsed = try SWFShapeParser.parseShapeWithStyle(&bits, version: version)
        return SWFShapeDefinition(
            characterId: characterId,
            bounds: bounds,
            edgeBounds: edgeBounds,
            usesFillWindingRule: windingRule,
            fillStyles: parsed.fillStyles,
            lineStyles: parsed.lineStyles,
            segments: parsed.segments
        )
    }

    /// Decodes a bare SHAPE structure (no style arrays) as used by DefineFont
    /// glyphs (spec chapter 6 "SHAPE", p. 125). Fill indices in the returned
    /// segments are the glyph convention: 0 = off, 1 = on. Shared with
    /// milestone 8.2.3 font decoding.
    public static func parseGlyphSegments(_ bits: inout SWFBitReader) throws -> [SWFShapeSegment] {
        try SWFShapeParser.parseGlyphShape(&bits)
    }
}

/// Which DefineShape tag a body came from. Drives the per-version rules: RGB
/// vs RGBA colors, extended 0xFF style counts, and LINESTYLE2.
nonisolated public enum SWFShapeVersion: Sendable {
    case shape1
    case shape2
    case shape3
    case shape4

    public init?(tagCode: UInt16) {
        switch tagCode {
        case 2: self = .shape1
        case 22: self = .shape2
        case 32: self = .shape3
        case 83: self = .shape4
        default: return nil
        }
    }

    /// DefineShape3/4 store RGBA everywhere DefineShape/2 store RGB (spec
    /// FILLSTYLE / LINESTYLE / GRADRECORD color columns).
    public var hasAlphaColors: Bool {
        self == .shape3 || self == .shape4
    }

    /// The 0xFF FillStyleCount escape to a UI16 extended count is "supported
    /// only for Shape2 and Shape3" (spec FILLSTYLEARRAY, p. 122) — and by
    /// DefineShape4, which extends DefineShape3. DefineShape reads 0xFF as a
    /// literal count of 255.
    public var supportsExtendedStyleCount: Bool {
        self != .shape1
    }

    /// DefineShape4 line styles are LINESTYLE2 (spec LINESTYLEARRAY, p. 123).
    public var usesLineStyle2: Bool {
        self == .shape4
    }
}
