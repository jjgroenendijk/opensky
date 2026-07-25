// Display-list control tag decoding: PlaceObject (4), PlaceObject2 (26),
// PlaceObject3 (70), RemoveObject (5), RemoveObject2 (28), and
// SetBackgroundColor (9). PlaceObject3's filter list and blend mode are
// decoded as framing only (counted + retained minimally, not rendered — the
// deferral is documented in docs/formats/swf.md). ClipActions are framed and
// their action streams parsed as of milestone 8.3.1 (see `SWFClipActions`);
// OpenSky still executes no ActionScript.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 3 "The
// display list" — PlaceObject (p. 34), PlaceObject2 (pp. 35-37), the CLIPACTIONS
// tables (pp. 36-37), PlaceObject3 (pp. 38-41), the filter records (pp. 42-47),
// ClipEventFlags (pp. 48-49), RemoveObject/RemoveObject2 (p. 50), and chapter 4
// "Control tags" SetBackgroundColor (p. 52).

import Foundation

nonisolated enum SWFDisplayListError: Error, Equatable {
    /// Tag code handed to a parser expecting a different display-list tag.
    case unsupportedTag(UInt16)
    /// A FILTERLIST entry carried an unknown FilterID, so the remaining tag
    /// body cannot be framed.
    case unknownFilterID(UInt8)
}

/// One decoded PlaceObject/PlaceObject2/PlaceObject3 tag. Optional members
/// mirror the tag's presence flags; `isMove` is PlaceFlagMove (PlaceObject2/3
/// modify-vs-place semantics).
nonisolated struct SWFPlacement: Equatable {
    var depth: UInt16 = 0
    var isMove = false
    var characterId: UInt16?
    var matrix: SWFMatrix?
    var colorTransform: SWFColorTransform?
    var ratio: UInt16?
    var name: String?
    var clipDepth: UInt16?
    /// PlaceObject3 only.
    var className: String?
    /// PlaceObject3 BlendMode byte (0/1 = normal), recorded + ignored.
    var blendMode: UInt8?
    /// PlaceObject3 SurfaceFilterList entry count, recorded + ignored.
    var filterCount = 0
    /// PlaceObject2/3 `PlaceFlagHasClipActions`.
    var hasClipActions = false
    /// The decoded CLIPACTIONS block, non-nil whenever `hasClipActions` is set.
    /// A block that could not be framed still lands here, carrying whatever
    /// handlers were read plus its warnings, so a malformed handler list never
    /// costs the tag its placement.
    var clipActions: SWFClipActions?
}

/// One RemoveObject/RemoveObject2 tag. RemoveObject also names the character
/// it expects at the depth; RemoveObject2 removes by depth alone.
nonisolated struct SWFRemoval: Equatable {
    let depth: UInt16
    let characterId: UInt16?
}

nonisolated enum SWFDisplayListParser {
    static let placeObjectCode: UInt16 = 4
    static let placeObject2Code: UInt16 = 26
    static let placeObject3Code: UInt16 = 70
    static let removeObjectCode: UInt16 = 5
    static let removeObject2Code: UInt16 = 28
    static let setBackgroundColorCode: UInt16 = 9
    static let showFrameCode: UInt16 = 1
    static let defineSpriteCode: UInt16 = 39

    /// Decodes any of the three PlaceObject tag versions. `version` is the
    /// movie's SWF version, which sets the CLIPEVENTFLAGS width; it defaults to
    /// 6 because every vanilla Interface movie is SWF 8 or later, so the wide
    /// form is the norm.
    static func parsePlacement(tag: SWFTag, version: UInt8 = 6) throws -> SWFPlacement {
        switch tag.code {
        case placeObjectCode: try parsePlaceObject(tag.body)
        case placeObject2Code: try parsePlaceObject2(tag.body, version: version)
        case placeObject3Code: try parsePlaceObject3(tag.body, version: version)
        default: throw SWFDisplayListError.unsupportedTag(tag.code)
        }
    }

    /// RemoveObject (5): CharacterId UI16 + Depth UI16.
    /// RemoveObject2 (28): Depth UI16.
    static func parseRemoval(tag: SWFTag) throws -> SWFRemoval {
        var bits = SWFBitReader(tag.body)
        switch tag.code {
        case removeObjectCode:
            let characterId = try bits.readAlignedUInt16()
            return try SWFRemoval(depth: bits.readAlignedUInt16(), characterId: characterId)
        case removeObject2Code:
            return try SWFRemoval(depth: bits.readAlignedUInt16(), characterId: nil)
        default:
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
    }

    /// SetBackgroundColor (9): RGB record.
    static func parseBackgroundColor(tag: SWFTag) throws -> SWFColor {
        guard tag.code == setBackgroundColorCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var bits = SWFBitReader(tag.body)
        return try SWFShapeParser.parseColor(&bits, hasAlpha: false)
    }

    /// PlaceObject (4): CharacterId, Depth, MATRIX, then an optional CXFORM
    /// (no alpha) filling the rest of the body. Always places a new character.
    private static func parsePlaceObject(_ body: Data) throws -> SWFPlacement {
        var bits = SWFBitReader(body)
        var placement = SWFPlacement()
        placement.characterId = try bits.readAlignedUInt16()
        placement.depth = try bits.readAlignedUInt16()
        placement.matrix = try SWFShapeParser.parseMatrix(&bits)
        bits.align()
        if bits.byteOffset < body.count {
            placement.colorTransform = try SWFColorTransform.parse(&bits, hasAlpha: false)
        }
        return placement
    }

    /// PlaceObject2 (26) flag byte, MSB -> LSB: HasClipActions, HasClipDepth,
    /// HasName, HasRatio, HasColorTransform, HasMatrix, HasCharacter, Move.
    private static func parsePlaceObject2(
        _ body: Data,
        version: UInt8
    ) throws -> SWFPlacement {
        var bits = SWFBitReader(body)
        let flags = try bits.readAlignedUInt8()
        var placement = SWFPlacement()
        placement.isMove = flags & 0x01 != 0
        placement.depth = try bits.readAlignedUInt16()
        try parseCommonFields(&bits, flags: flags, into: &placement)
        readClipActions(&bits, flags: flags, version: version, into: &placement)
        return placement
    }

    /// PlaceObject3 (70): the PlaceObject2 flag byte plus a second flag byte
    /// (MSB -> LSB: Reserved, OpaqueBackground, HasVisible, HasImage,
    /// HasClassName, HasCacheAsBitmap, HasBlendMode, HasFilterList), with the
    /// class name inserted before the character id and the filter/blend/cache/
    /// visibility fields after the clip depth.
    private static func parsePlaceObject3(
        _ body: Data,
        version: UInt8
    ) throws -> SWFPlacement {
        var bits = SWFBitReader(body)
        let flags = try bits.readAlignedUInt8()
        let flags2 = try bits.readAlignedUInt8()
        var placement = SWFPlacement()
        placement.isMove = flags & 0x01 != 0
        placement.depth = try bits.readAlignedUInt16()
        let hasImage = flags2 & 0x10 != 0
        let hasCharacter = flags & 0x02 != 0
        if flags2 & 0x08 != 0 || (hasImage && hasCharacter) {
            placement.className = try readString(&bits)
        }
        try parseCommonFields(&bits, flags: flags, into: &placement)
        if flags2 & 0x01 != 0 {
            placement.filterCount = try skipFilterList(&bits)
        }
        if flags2 & 0x02 != 0 {
            placement.blendMode = try bits.readAlignedUInt8()
        }
        if flags2 & 0x04 != 0 {
            _ = try bits.readAlignedUInt8() // BitmapCache, recorded implicitly
        }
        if flags2 & 0x20 != 0 {
            _ = try bits.readAlignedUInt8() // Visible
        }
        if flags2 & 0x40 != 0 {
            _ = try SWFShapeParser.parseColor(&bits, hasAlpha: true) // BackgroundColor
        }
        readClipActions(&bits, flags: flags, version: version, into: &placement)
        return placement
    }

    /// CLIPACTIONS closes both PlaceObject2 and PlaceObject3 when
    /// `PlaceFlagHasClipActions` (0x80) is set. Parsing never throws, so a
    /// malformed handler list costs the block, not the placement.
    private static func readClipActions(
        _ bits: inout SWFBitReader,
        flags: UInt8,
        version: UInt8,
        into placement: inout SWFPlacement
    ) {
        guard flags & 0x80 != 0 else {
            return
        }
        placement.hasClipActions = true
        placement.clipActions = SWFClipActionsParser.parse(&bits, version: version)
    }

    /// The field run shared by PlaceObject2 and PlaceObject3: CharacterId,
    /// MATRIX, CXFORMWITHALPHA, Ratio, Name, ClipDepth, gated by the first
    /// flag byte in that order.
    private static func parseCommonFields(
        _ bits: inout SWFBitReader,
        flags: UInt8,
        into placement: inout SWFPlacement
    ) throws {
        if flags & 0x02 != 0 {
            placement.characterId = try bits.readAlignedUInt16()
        }
        if flags & 0x04 != 0 {
            placement.matrix = try SWFShapeParser.parseMatrix(&bits)
        }
        if flags & 0x08 != 0 {
            placement.colorTransform = try SWFColorTransform.parse(&bits, hasAlpha: true)
        }
        if flags & 0x10 != 0 {
            placement.ratio = try bits.readAlignedUInt16()
        }
        if flags & 0x20 != 0 {
            placement.name = try readString(&bits)
        }
        if flags & 0x40 != 0 {
            placement.clipDepth = try bits.readAlignedUInt16()
        }
    }

    /// FILTERLIST framing (spec pp. 143-151): NumberOfFilters UI8, then one
    /// FILTER per entry, each a FilterID byte plus a body whose size the ID
    /// determines. Filters are not rendered — this only frames past them so
    /// the fields after the list stay readable — but the count is returned so
    /// the sweep can tally the deferral.
    private static func skipFilterList(_ bits: inout SWFBitReader) throws -> Int {
        let count = try Int(bits.readAlignedUInt8())
        for _ in 0 ..< count {
            let filterID = try bits.readAlignedUInt8()
            let fixedSize: Int
            switch filterID {
            case 0: fixedSize = 23 // DropShadow
            case 1: fixedSize = 9 // Blur
            case 2: fixedSize = 15 // Glow
            case 3: fixedSize = 27 // Bevel
            case 4, 7: // GradientGlow / GradientBevel: NumColors UI8 + 5/color
                let colors = try Int(bits.readAlignedUInt8())
                fixedSize = colors * 5 + 19
            case 5: // Convolution: MatrixX/Y UI8 + FLOAT matrix + fixed tail
                let matrixX = try Int(bits.readAlignedUInt8())
                let matrixY = try Int(bits.readAlignedUInt8())
                fixedSize = 4 + 4 + matrixX * matrixY * 4 + 4 + 1
            case 6: fixedSize = 80 // ColorMatrix: 20 FLOATs
            default: throw SWFDisplayListError.unknownFilterID(filterID)
            }
            try skipBytes(&bits, count: fixedSize)
        }
        return count
    }

    private static func skipBytes(_ bits: inout SWFBitReader, count: Int) throws {
        bits.align()
        guard bits.remainingData.count >= count else {
            throw SWFBitReaderError.outOfBounds(
                bitsRequested: count * 8, bitsRemaining: bits.remainingData.count * 8
            )
        }
        bits.advance(byteCount: count)
    }

    /// Null-terminated UTF-8 STRING (SWF 6+) with a CP1252 fallback, matching
    /// the SWFEditText string convention.
    private static func readString(_ bits: inout SWFBitReader) throws -> String {
        bits.align()
        var reader = BinaryReader(bits.remainingData)
        let bytes = try reader.readZStringData()
        bits.advance(byteCount: reader.offset)
        return String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
    }
}
