// DefineEditText (37): a dynamic or input text field. For HTML fields the
// markup is kept and a plain-text version is made by stripping tags.
// Layout and sources: docs/formats/swf-text.md.

import Foundation
import OpenSkyFormatsCore

/// The DefineEditText flag word (spec p. 176), one bit per capability.
nonisolated public struct SWFEditTextFlags: Equatable, Sendable {
    public var hasText = false
    public var wordWrap = false
    public var multiline = false
    public var password = false
    public var readOnly = false
    public var hasTextColor = false
    public var hasMaxLength = false
    public var hasFont = false
    public var hasFontClass = false
    public var autoSize = false
    public var hasLayout = false
    public var noSelect = false
    public var border = false
    public var wasStatic = false
    public var html = false
    public var useOutlines = false
}

/// The optional DefineEditText paragraph layout block (spec p. 177).
nonisolated public struct SWFEditTextLayout: Equatable, Sendable {
    /// 0 left, 1 right, 2 center, 3 justify.
    public let align: UInt8
    public let leftMargin: UInt16
    public let rightMargin: UInt16
    public let indent: UInt16
    public let leading: Int16
}

/// A decoded DefineEditText character.
nonisolated public struct SWFEditText: Equatable, Sendable {
    /// The tag code this parser accepts.
    public static let tagCode: UInt16 = 37

    public let characterId: UInt16
    public let bounds: SWFRect
    public let flags: SWFEditTextFlags
    public let fontID: UInt16?
    public let fontClass: String?
    /// Font height in twips; present when a font id or font class is set.
    public let fontHeight: UInt16?
    public let color: SWFColor?
    public let maxLength: UInt16?
    public let layout: SWFEditTextLayout?
    public let variableName: String
    /// The InitialText string exactly as stored (may contain HTML markup when
    /// `flags.html` is set), or nil when the field carries no initial text.
    public let initialText: String?

    /// Plain-text view of `initialText`: markup stripped when the field is HTML,
    /// otherwise the stored string. Full HTML text layout is deferred to 8.3.x.
    public var plainText: String? {
        guard let initialText else { return nil }
        return flags.html ? SWFEditText.stripHTML(initialText) : initialText
    }

    /// Decodes a DefineEditText (37) tag body.
    public static func parse(tag: SWFTag) throws -> SWFEditText {
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

    /// A null-terminated STRING read from the current byte position. SWF 6 and
    /// later declare strings UTF-8, older movies carry code-page bytes, so this
    /// takes the engine-wide `GameText` policy and never fails the parse.
    private static func readString(_ bits: inout SWFBitReader) throws -> String {
        bits.align()
        var reader = BinaryReader(bits.remainingData)
        let bytes = try reader.readZStringData()
        bits.advance(byteCount: reader.offset)
        return GameText.decode(bytes)
    }

    /// Removes `<...>` markup for the plain-text fallback. Deliberately minimal:
    /// it does not decode entities or honor tag semantics — HTML text layout is
    /// 8.3.x work, this only yields readable content for static rendering.
    public static func stripHTML(_ text: String) -> String {
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
