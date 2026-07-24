// Synthetic display-list tag builders (PlaceObject/2/3, RemoveObject/2,
// SetBackgroundColor, DefineSprite) plus a rectangle-shape helper, assembled
// bit-by-bit following the Adobe SWF File Format Specification v19 chapters 3
// and 6 — never extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky

enum SWFDisplayFixture {
    /// MATRIX fields for a place tag; scale/rotate write as 16.16 fixed point.
    struct MatrixSpec {
        var scaleX: Float?
        var scaleY: Float?
        var rotateSkew0: Float?
        var rotateSkew1: Float?
        var translateX: Int32 = 0
        var translateY: Int32 = 0
    }

    /// CXFORM terms as raw SB values: multiply in 8.8 fixed (256 = 1.0), add
    /// in the -255..255 integer domain.
    struct CxformSpec {
        var multiplyTerms: [Int32]?
        var addTerms: [Int32]?
        var nbits = 12
    }

    struct Place2 {
        var depth: UInt16 = 1
        var move = false
        var characterId: UInt16?
        var matrix: MatrixSpec?
        var cxform: CxformSpec?
        var ratio: UInt16?
        var name: String?
        var clipDepth: UInt16?
    }

    struct Place3 {
        var place = Place2()
        var className: String?
        var blendMode: UInt8?
        /// Encoded as blur filters (FilterID 1, 9-byte bodies).
        var blurFilterCount = 0
    }

    /// DefineShape (2): an axis-aligned solid-color rectangle in twips.
    static func rectangleShapeTag(
        characterId: UInt16,
        width: Int32,
        height: Int32,
        color: SWFColor
    ) -> SWFFixture.Tag {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(characterId)
        builder.appendRect(xMin: 0, xMax: width, yMin: 0, yMax: height)
        builder.appendStyleCount(1)
        builder.appendSolidFill(color, rgba: false)
        builder.appendStyleCount(0)
        builder.appendIndexBits(fill: 1, line: 0)
        var change = SWFShapeBodyBuilder.StyleChange(moveToX: 0, moveToY: 0)
        change.fill1 = 1
        builder.appendStyleChange(change)
        builder.appendAxisEdge(delta: width, vertical: false)
        builder.appendAxisEdge(delta: height, vertical: true)
        builder.appendAxisEdge(delta: -width, vertical: false)
        builder.appendAxisEdge(delta: -height, vertical: true)
        builder.appendEndRecord()
        return SWFFixture.Tag(code: 2, body: builder.build())
    }

    /// PlaceObject (4): character id + depth + MATRIX + optional CXFORM.
    static func placeObjectTag(
        characterId: UInt16,
        depth: UInt16,
        matrix: MatrixSpec = MatrixSpec(),
        cxform: CxformSpec? = nil
    ) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(characterId)
        writer.appendUInt16LE(depth)
        writeMatrix(&writer, matrix)
        if let cxform {
            writeCxform(&writer, cxform, hasAlpha: false)
        }
        writer.align()
        return SWFFixture.Tag(code: 4, body: writer.bytes())
    }

    static func placeObject2Tag(_ place: Place2) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendByte(place2Flags(place))
        writer.appendUInt16LE(place.depth)
        writeCommonFields(&writer, place)
        writer.align()
        return SWFFixture.Tag(code: 26, body: writer.bytes())
    }

    static func placeObject3Tag(_ place3: Place3) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendByte(place2Flags(place3.place))
        var flags2: UInt8 = 0
        if place3.blurFilterCount > 0 {
            flags2 |= 0x01
        }
        if place3.blendMode != nil {
            flags2 |= 0x02
        }
        if place3.className != nil {
            flags2 |= 0x08
        }
        writer.appendByte(flags2)
        writer.appendUInt16LE(place3.place.depth)
        if let className = place3.className {
            writeString(&writer, className)
        }
        writeCommonFields(&writer, place3.place)
        if place3.blurFilterCount > 0 {
            writer.appendByte(UInt8(place3.blurFilterCount))
            for _ in 0 ..< place3.blurFilterCount {
                writer.appendByte(1) // FilterID Blur
                writer.appendBytes([UInt8](repeating: 0, count: 9))
            }
        }
        if let blendMode = place3.blendMode {
            writer.appendByte(blendMode)
        }
        writer.align()
        return SWFFixture.Tag(code: 70, body: writer.bytes())
    }

    static func removeObjectTag(characterId: UInt16, depth: UInt16) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(characterId)
        writer.appendUInt16LE(depth)
        return SWFFixture.Tag(code: 5, body: writer.bytes())
    }

    static func removeObject2Tag(depth: UInt16) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(depth)
        return SWFFixture.Tag(code: 28, body: writer.bytes())
    }

    static var showFrameTag: SWFFixture.Tag {
        SWFFixture.Tag(code: 1, body: Data())
    }

    static func backgroundColorTag(_ color: SWFColor) -> SWFFixture.Tag {
        SWFFixture.Tag(code: 9, body: Data([color.red, color.green, color.blue]))
    }

    /// DefineSprite (39): id + frame count + nested control tags + End.
    static func spriteTag(
        characterId: UInt16,
        frameCount: UInt16,
        tags: [SWFFixture.Tag]
    ) -> SWFFixture.Tag {
        var body = Data()
        body.appendUInt16(characterId)
        body.appendUInt16(frameCount)
        for tag in tags {
            body.append(SWFFixture.tagBytes(code: tag.code, body: tag.body))
        }
        body.append(SWFFixture.tagBytes(code: 0, body: Data()))
        return SWFFixture.Tag(code: 39, body: body)
    }

    /// Builds a movie from tags (End appended by the fixture).
    static func movie(
        tags: [SWFFixture.Tag],
        frameWidthTwips: Int32 = 8000,
        frameHeightTwips: Int32 = 6000
    ) throws -> SWFMovie {
        var fixture = SWFFixture()
        fixture.xMax = frameWidthTwips
        fixture.yMax = frameHeightTwips
        fixture.tags = tags
        return try SWFMovie(file: SWFFile(data: fixture.build()))
    }
}

// MARK: - Record writers

extension SWFDisplayFixture {
    fileprivate static func place2Flags(_ place: Place2) -> UInt8 {
        var flags: UInt8 = 0
        if place.move {
            flags |= 0x01
        }
        if place.characterId != nil {
            flags |= 0x02
        }
        if place.matrix != nil {
            flags |= 0x04
        }
        if place.cxform != nil {
            flags |= 0x08
        }
        if place.ratio != nil {
            flags |= 0x10
        }
        if place.name != nil {
            flags |= 0x20
        }
        if place.clipDepth != nil {
            flags |= 0x40
        }
        return flags
    }

    fileprivate static func writeCommonFields(_ writer: inout SWFBitWriter, _ place: Place2) {
        if let characterId = place.characterId {
            writer.appendUInt16LE(characterId)
        }
        if let matrix = place.matrix {
            writeMatrix(&writer, matrix)
        }
        if let cxform = place.cxform {
            writeCxform(&writer, cxform, hasAlpha: true)
        }
        if let ratio = place.ratio {
            writer.appendUInt16LE(ratio)
        }
        if let name = place.name {
            writeString(&writer, name)
        }
        if let clipDepth = place.clipDepth {
            writer.appendUInt16LE(clipDepth)
        }
    }

    /// MATRIX record: optional 16.16 scale pair, optional 16.16 rotate pair,
    /// then twip translation (spec p. 23).
    static func writeMatrix(_ writer: inout SWFBitWriter, _ matrix: MatrixSpec) {
        writer.align()
        if let scaleX = matrix.scaleX ?? matrix.scaleY {
            let rawX = Int32(scaleX * 65536)
            let rawY = Int32((matrix.scaleY ?? scaleX) * 65536)
            writer.writeUB(1, count: 1)
            let nbits = max(
                SWFFixture.signedBitWidth(rawX), SWFFixture.signedBitWidth(rawY)
            )
            writer.writeUB(UInt32(nbits), count: 5)
            writer.writeSB(rawX, count: nbits)
            writer.writeSB(rawY, count: nbits)
        } else {
            writer.writeUB(0, count: 1)
        }
        if let rotate0 = matrix.rotateSkew0 ?? matrix.rotateSkew1 {
            let raw0 = Int32(rotate0 * 65536)
            let raw1 = Int32((matrix.rotateSkew1 ?? 0) * 65536)
            writer.writeUB(1, count: 1)
            let nbits = max(
                SWFFixture.signedBitWidth(raw0), SWFFixture.signedBitWidth(raw1)
            )
            writer.writeUB(UInt32(nbits), count: 5)
            writer.writeSB(raw0, count: nbits)
            writer.writeSB(raw1, count: nbits)
        } else {
            writer.writeUB(0, count: 1)
        }
        let nbits = max(
            SWFFixture.signedBitWidth(matrix.translateX),
            SWFFixture.signedBitWidth(matrix.translateY)
        )
        writer.writeUB(UInt32(nbits), count: 5)
        writer.writeSB(matrix.translateX, count: nbits)
        writer.writeSB(matrix.translateY, count: nbits)
    }

    /// CXFORM(WITHALPHA): HasAdd, HasMult, Nbits, mult terms then add terms
    /// (spec pp. 24-25). Channel count 3 (RGB) or 4 (RGBA).
    static func writeCxform(
        _ writer: inout SWFBitWriter,
        _ cxform: CxformSpec,
        hasAlpha: Bool
    ) {
        writer.align()
        writer.writeUB(cxform.addTerms != nil ? 1 : 0, count: 1)
        writer.writeUB(cxform.multiplyTerms != nil ? 1 : 0, count: 1)
        writer.writeUB(UInt32(cxform.nbits), count: 4)
        let channels = hasAlpha ? 4 : 3
        if let terms = cxform.multiplyTerms {
            for channel in 0 ..< channels {
                writer.writeSB(channel < terms.count ? terms[channel] : 256, count: cxform.nbits)
            }
        }
        if let terms = cxform.addTerms {
            for channel in 0 ..< channels {
                writer.writeSB(channel < terms.count ? terms[channel] : 0, count: cxform.nbits)
            }
        }
    }

    fileprivate static func writeString(_ writer: inout SWFBitWriter, _ string: String) {
        writer.appendBytes(Array(string.utf8))
        writer.appendByte(0)
    }
}
