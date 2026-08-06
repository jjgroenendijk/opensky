// DefineEditText (37): a dynamic/input text field definition — bounds, a large
// flag word, an optional font + height, color, layout, a variable name, and
// optional initial text. For static rendering the plain-text content is the
// target; when the field is flagged HTML the markup is recorded and the tags
// stripped for a plain-text fallback (full HTML text layout is 8.3.x work).
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10
// "Fonts and Text" — DefineEditText (pp. 175-177). Documented in
// docs/formats/swf.md.

import Foundation

/// The DefineEditText flag word (spec p. 176), one bit per capability.
nonisolated struct SWFEditTextFlags: Equatable {
    var hasText = false
    var wordWrap = false
    var multiline = false
    var password = false
    var readOnly = false
    var hasTextColor = false
    var hasMaxLength = false
    var hasFont = false
    var hasFontClass = false
    var autoSize = false
    var hasLayout = false
    var noSelect = false
    var border = false
    var wasStatic = false
    var html = false
    var useOutlines = false
}

/// The optional DefineEditText paragraph layout block (spec p. 177).
nonisolated struct SWFEditTextLayout: Equatable {
    /// 0 left, 1 right, 2 center, 3 justify.
    let align: UInt8
    let leftMargin: UInt16
    let rightMargin: UInt16
    let indent: UInt16
    let leading: Int16
}

/// A decoded DefineEditText character.
nonisolated struct SWFEditText: Equatable {
    /// The tag code this parser accepts.
    static let tagCode: UInt16 = 37

    let characterId: UInt16
    let bounds: SWFRect
    let flags: SWFEditTextFlags
    let fontID: UInt16?
    let fontClass: String?
    /// Font height in twips; present when a font id or font class is set.
    let fontHeight: UInt16?
    let color: SWFColor?
    let maxLength: UInt16?
    let layout: SWFEditTextLayout?
    let variableName: String
    /// The InitialText string exactly as stored (may contain HTML markup when
    /// `flags.html` is set), or nil when the field carries no initial text.
    let initialText: String?

    /// Plain-text view of `initialText`: markup stripped when the field is HTML,
    /// otherwise the stored string. Full HTML text layout is deferred to 8.3.x.
    var plainText: String? {
        guard let initialText else { return nil }
        return flags.html ? SWFEditText.stripHTML(initialText) : initialText
    }

    /// Decodes a DefineEditText (37) tag body.
    static func parse(tag: SWFTag) throws -> SWFEditText {
        guard tag.code == tagCode else {
            throw SWFTextError.unsupportedTag(tag.code)
        }
        var bits = SWFBitReader(tag.body)
        let characterId = try bits.readAlignedUInt16()
        let bounds = try SWFShapeParser.parseRect(&bits)
        bits.align()
        let flags = try parseFlags(&bits)
        let fonts = try parseFontFields(&bits, flags: flags)
        let color = try flags.hasTextColor
            ? SWFShapeParser.parseColor(&bits, hasAlpha: true) : nil
        let maxLength = try flags.hasMaxLength ? Int(bits.readAlignedUInt16()) : nil
        let layout = try flags.hasLayout ? parseLayout(&bits) : nil
        let variableName = try readString(&bits)
        let initialText = try flags.hasText ? readString(&bits) : nil
        return SWFEditText(
            characterId: characterId, bounds: bounds, flags: flags,
            fontID: fonts.fontID, fontClass: fonts.fontClass, fontHeight: fonts.fontHeight,
            color: color, maxLength: maxLength.map(UInt16.init), layout: layout,
            variableName: variableName, initialText: initialText
        )
    }

    /// The 16-bit flag word, read MSB first in spec field order.
    private static func parseFlags(_ bits: inout SWFBitReader) throws -> SWFEditTextFlags {
        func flag() throws -> Bool {
            try bits.readUB(1) == 1
        }
        var flags = SWFEditTextFlags()
        flags.hasText = try flag()
        flags.wordWrap = try flag()
        flags.multiline = try flag()
        flags.password = try flag()
        flags.readOnly = try flag()
        flags.hasTextColor = try flag()
        flags.hasMaxLength = try flag()
        flags.hasFont = try flag()
        flags.hasFontClass = try flag()
        flags.autoSize = try flag()
        flags.hasLayout = try flag()
        flags.noSelect = try flag()
        flags.border = try flag()
        flags.wasStatic = try flag()
        flags.html = try flag()
        flags.useOutlines = try flag()
        return flags
    }

    private struct FontFields {
        let fontID: UInt16?
        let fontClass: String?
        let fontHeight: UInt16?
    }

    /// FontID (HasFont), FontClass (HasFontClass), and FontHeight (present when
    /// either is set) — spec p. 176.
    private static func parseFontFields(
        _ bits: inout SWFBitReader,
        flags: SWFEditTextFlags
    ) throws -> FontFields {
        let fontID = try flags.hasFont ? bits.readAlignedUInt16() : nil
        let fontClass = try flags.hasFontClass ? readString(&bits) : nil
        let fontHeight = try flags.hasFont || flags.hasFontClass
            ? bits.readAlignedUInt16() : nil
        return FontFields(fontID: fontID, fontClass: fontClass, fontHeight: fontHeight)
    }

    private static func parseLayout(_ bits: inout SWFBitReader) throws -> SWFEditTextLayout {
        try SWFEditTextLayout(
            align: bits.readAlignedUInt8(),
            leftMargin: bits.readAlignedUInt16(),
            rightMargin: bits.readAlignedUInt16(),
            indent: bits.readAlignedUInt16(),
            leading: Int16(bitPattern: bits.readAlignedUInt16())
        )
    }

    /// A null-terminated UTF-8 STRING (SWF 6+) read from the current byte
    /// position; falls back to CP1252 so a stray byte never fails the parse.
    private static func readString(_ bits: inout SWFBitReader) throws -> String {
        bits.align()
        var reader = BinaryReader(bits.remainingData)
        let bytes = try reader.readZStringData()
        bits.advance(byteCount: reader.offset)
        return String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
    }

    /// Removes `<...>` markup for the plain-text fallback. Deliberately minimal:
    /// it does not decode entities or honor tag semantics — HTML text layout is
    /// 8.3.x work, this only yields readable content for static rendering.
    static func stripHTML(_ text: String) -> String {
        var result = ""
        var insideTag = false
        for character in text {
            if character == "<" {
                insideTag = true
            } else if character == ">" {
                insideTag = false
            } else if !insideTag {
                result.append(character)
            }
        }
        return result
    }
}
