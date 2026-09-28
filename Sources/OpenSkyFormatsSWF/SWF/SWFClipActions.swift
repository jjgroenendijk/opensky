// CLIPACTIONS decoding: the per-event ActionScript handlers a PlaceObject2 (26)
// or PlaceObject3 (70) tag attaches to a placed sprite (`onPress`,
// `onEnterFrame`, and the rest). Before milestone 8.3.1 the display-list parser
// only recorded that the block was present and stopped reading; it is now
// framed and its action streams parsed.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 3 "The
// display list" — the CLIPACTIONS and CLIPACTIONRECORD tables under
// "PlaceObject2" (pp. 36-37) and "ClipEventFlags" (pp. 48-49).

import Foundation
import OpenSkyFormatsCore

/// CLIPEVENTFLAGS: the sprite events one handler applies to. Stored as the raw
/// little-endian flag word so reserved bits survive a round trip. The field is
/// 2 bytes through SWF 5 and 4 bytes from SWF 6, and the events above
/// `dragOver` only exist in the wide form.
nonisolated public struct SWFClipEventFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let load = SWFClipEventFlags(rawValue: 1 << 0)
    public static let enterFrame = SWFClipEventFlags(rawValue: 1 << 1)
    public static let unload = SWFClipEventFlags(rawValue: 1 << 2)
    public static let mouseMove = SWFClipEventFlags(rawValue: 1 << 3)
    public static let mouseDown = SWFClipEventFlags(rawValue: 1 << 4)
    public static let mouseUp = SWFClipEventFlags(rawValue: 1 << 5)
    public static let keyDown = SWFClipEventFlags(rawValue: 1 << 6)
    public static let keyUp = SWFClipEventFlags(rawValue: 1 << 7)
    public static let data = SWFClipEventFlags(rawValue: 1 << 8)
    public static let initialize = SWFClipEventFlags(rawValue: 1 << 9)
    public static let press = SWFClipEventFlags(rawValue: 1 << 10)
    public static let release = SWFClipEventFlags(rawValue: 1 << 11)
    public static let releaseOutside = SWFClipEventFlags(rawValue: 1 << 12)
    public static let rollOver = SWFClipEventFlags(rawValue: 1 << 13)
    public static let rollOut = SWFClipEventFlags(rawValue: 1 << 14)
    public static let dragOver = SWFClipEventFlags(rawValue: 1 << 15)
    public static let dragOut = SWFClipEventFlags(rawValue: 1 << 16)
    public static let keyPress = SWFClipEventFlags(rawValue: 1 << 17)
    public static let construct = SWFClipEventFlags(rawValue: 1 << 18)
}

/// One CLIPACTIONRECORD: the events it handles, the key it traps for a
/// `keyPress` handler, and its parsed action stream.
nonisolated public struct SWFClipActionRecord: Equatable, Sendable {
    public let events: SWFClipEventFlags
    /// `KeyCode`, present only when `events` contains `keyPress`.
    public let keyCode: UInt8?
    public let actions: SWFActionBlock
}

/// A decoded CLIPACTIONS block.
nonisolated public struct SWFClipActions: Equatable, Sendable {
    /// `AllEventFlags`: the union the tag declares, kept as written rather than
    /// recomputed, so a movie that disagrees with itself stays inspectable.
    public let allEvents: SWFClipEventFlags
    public let records: [SWFClipActionRecord]
    /// Framing problems in the CLIPACTIONS block itself. Non-empty means
    /// handlers after the failure were not recovered.
    public let warnings: [SWFActionWarning]
}

nonisolated public enum SWFClipActionsParser: Sendable {
    /// Frames a CLIPACTIONS block starting at the reader's current byte, and
    /// leaves the reader just past it. Never throws: a malformed block yields
    /// whatever handlers were framed plus a warning, because a place tag with
    /// bad clip actions must still place its character.
    public static func parse(_ bits: inout SWFBitReader, version: UInt8) -> SWFClipActions {
        bits.align()
        var decoder = ClipActionsDecoder(base: bits.byteOffset, version: version)
        var reader = BinaryReader(bits.remainingData)
        decoder.run(&reader)
        bits.advance(byteCount: reader.offset)
        return decoder.clipActions
    }

    /// CLIPEVENTFLAGS is UI16 through SWF 5 and UI32 from SWF 6. Both are
    /// little-endian, and the narrow form is the low half of the wide one, so
    /// one flag layout serves both.
    public static func flagWidth(version: UInt8) -> Int {
        version >= 6 ? 4 : 2
    }
}

/// Sequential CLIPACTIONRECORD reader. `base` is the byte offset of the block
/// inside the place tag body, so a warning names a position in the tag rather
/// than in the slice.
nonisolated private struct ClipActionsDecoder {
    let base: Int
    let version: UInt8
    private var allEvents = SWFClipEventFlags(rawValue: 0)
    private var records: [SWFClipActionRecord] = []
    private var warnings: [SWFActionWarning] = []

    init(base: Int, version: UInt8) {
        self.base = base
        self.version = version
    }

    var clipActions: SWFClipActions {
        SWFClipActions(allEvents: allEvents, records: records, warnings: warnings)
    }

    mutating func run(_ reader: inout BinaryReader) {
        // Reserved UI16 (must be 0), then the declared union of events.
        guard
            (try? reader.readUInt16()) != nil,
            let declared = readFlags(&reader)
        else {
            warnings.append(.malformedClipActions(offset: base))
            return
        }
        allEvents = declared
        while step(&reader) {
            continue
        }
    }

    /// Reads one CLIPACTIONRECORD. Returns false at the terminating all-zero
    /// `ClipActionEndFlag`, at the end of the data, or on a framing failure.
    private mutating func step(_ reader: inout BinaryReader) -> Bool {
        let offset = base + reader.offset
        guard let events = readFlags(&reader) else {
            warnings.append(.malformedClipActions(offset: offset))
            return false
        }
        if events.isEmpty {
            return false // ClipActionEndFlag
        }
        guard let size = try? Int(reader.readUInt32()), size <= reader.bytesRemaining else {
            warnings.append(.malformedClipActions(offset: offset))
            return false
        }
        // ActionRecordSize spans from the end of that field to the next record,
        // so the KeyCode byte of a keyPress handler is inside it.
        var keyCode: UInt8?
        var actionSize = size
        if events.contains(.keyPress) {
            guard size >= 1, let code = try? reader.readUInt8() else {
                warnings.append(.malformedClipActions(offset: offset))
                return false
            }
            keyCode = code
            actionSize = size - 1
        }
        guard let bytes = try? reader.read(count: actionSize) else {
            warnings.append(.malformedClipActions(offset: offset))
            return false
        }
        records.append(
            SWFClipActionRecord(
                events: events, keyCode: keyCode, actions: SWFActionParser.parse(bytes)
            )
        )
        return true
    }

    private func readFlags(_ reader: inout BinaryReader) -> SWFClipEventFlags? {
        if SWFClipActionsParser.flagWidth(version: version) == 4 {
            return (try? reader.readUInt32()).map(SWFClipEventFlags.init(rawValue:))
        }
        return (try? reader.readUInt16())
            .map { SWFClipEventFlags(rawValue: UInt32($0)) }
    }
}
