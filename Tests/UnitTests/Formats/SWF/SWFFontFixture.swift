// Synthetic DefineFont2/DefineFont3 tag-body builder for font parser tests.
// Bodies are assembled byte-by-byte in code following the Adobe SWF File Format
// Specification v19 chapter 10 layouts — never extracted game files
// (AGENTS.md "Legal & IP boundary"). Glyph shapes reuse SWFShapeBodyBuilder.

import Foundation
@testable import opensky

/// Assembles a DefineFont2 (48) / DefineFont3 (75) tag body. `flags` drives the
/// offset/code integer widths; the offset table is computed from the glyph
/// shape sizes so the parser's slice math is exercised for real.
struct SWFFontBodyBuilder {
    /// Layout block written only when `flags.hasLayout` is set.
    struct Layout {
        var ascent: Int16 = 0
        var descent: Int16 = 0
        var leading: Int16 = 0
        var advances: [Int16] = []
        var bounds: [SWFRect] = []
        var kerning: [SWFKerningRecord] = []
    }

    var fontID: UInt16 = 1
    var flags = SWFFontFlags()
    var languageCode: UInt8 = 0
    var name = "TestFont"
    var codes: [UInt16] = []
    /// One bare glyph SHAPE (NumFillBits/NumLineBits + records) per glyph.
    var shapes: [Data] = []
    var layout: Layout?

    /// A bare glyph SHAPE for a filled triangle spanning `size` glyph units,
    /// starting at the origin (SWF glyph space is y-down).
    static func triangleGlyphShape(size: Int32) -> Data {
        glyphShape { builder in
            var change = SWFShapeBodyBuilder.StyleChange(moveToX: 0, moveToY: 0)
            change.fill1 = 1
            builder.appendStyleChange(change)
            builder.appendStraightEdge(deltaX: size, deltaY: 0)
            builder.appendStraightEdge(deltaX: -size, deltaY: size)
            builder.appendStraightEdge(deltaX: 0, deltaY: -size)
        }
    }

    /// Wraps glyph records in the bare-SHAPE framing (index bits + end record).
    static func glyphShape(_ records: (inout SWFShapeBodyBuilder) -> Void) -> Data {
        var builder = SWFShapeBodyBuilder()
        builder.appendIndexBits(fill: 1, line: 0)
        records(&builder)
        builder.appendEndRecord()
        return builder.build()
    }

    func build() -> Data {
        var out = Data()
        out.appendUInt16(fontID)
        out.append(flagsByte())
        out.append(languageCode)
        let nameBytes = Array(name.utf8)
        out.append(UInt8(nameBytes.count))
        out.append(contentsOf: nameBytes)
        out.appendUInt16(UInt16(shapes.count))
        appendOffsetTable(into: &out)
        for shape in shapes {
            out.append(shape)
        }
        appendCodeTable(into: &out)
        if let layout {
            appendLayout(layout, into: &out)
        }
        return out
    }

    private func flagsByte() -> UInt8 {
        var byte: UInt8 = 0
        if flags.hasLayout {
            byte |= 0x80
        }
        if flags.shiftJIS {
            byte |= 0x40
        }
        if flags.smallText {
            byte |= 0x20
        }
        if flags.ansi {
            byte |= 0x10
        }
        if flags.wideOffsets {
            byte |= 0x08
        }
        if flags.wideCodes {
            byte |= 0x04
        }
        if flags.italic {
            byte |= 0x02
        }
        if flags.bold {
            byte |= 0x01
        }
        return byte
    }

    private func appendOffsetTable(into out: inout Data) {
        let entrySize = flags.wideOffsets ? 4 : 2
        let tableSize = (shapes.count + 1) * entrySize
        var offset = tableSize
        var values: [Int] = []
        for shape in shapes {
            values.append(offset)
            offset += shape.count
        }
        values.append(offset) // CodeTableOffset
        for value in values {
            if flags.wideOffsets {
                out.appendUInt32(UInt32(value))
            } else {
                out.appendUInt16(UInt16(value))
            }
        }
    }

    private func appendCodeTable(into out: inout Data) {
        for code in codes {
            if flags.wideCodes {
                out.appendUInt16(code)
            } else {
                out.append(UInt8(code & 0xFF))
            }
        }
    }

    private func appendLayout(_ layout: Layout, into out: inout Data) {
        out.appendUInt16(UInt16(bitPattern: layout.ascent))
        out.appendUInt16(UInt16(bitPattern: layout.descent))
        out.appendUInt16(UInt16(bitPattern: layout.leading))
        for advance in layout.advances {
            out.appendUInt16(UInt16(bitPattern: advance))
        }
        var writer = SWFBitWriter()
        for rect in layout.bounds {
            writer.align()
            let fields = [rect.xMin, rect.xMax, rect.yMin, rect.yMax]
            let nbits = fields.map(SWFFixture.signedBitWidth).max() ?? 1
            writer.writeUB(UInt32(nbits), count: 5)
            for field in fields {
                writer.writeSB(field, count: nbits)
            }
        }
        writer.align()
        out.append(writer.bytes())
        out.appendUInt16(UInt16(layout.kerning.count))
        for record in layout.kerning {
            if flags.wideCodes {
                out.appendUInt16(record.code1)
                out.appendUInt16(record.code2)
            } else {
                out.append(UInt8(record.code1 & 0xFF))
                out.append(UInt8(record.code2 & 0xFF))
            }
            out.appendUInt16(UInt16(bitPattern: record.adjustment))
        }
    }
}
