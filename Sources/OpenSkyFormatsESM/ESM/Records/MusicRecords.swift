// MUSC music types (playlist and transition policy) and MUST music tracks
// (file, loop, and finale data). Layout and sources: docs/formats/music.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MusicType: Sendable {
    /// FNAM bitfield. Bit 0x10 is unnamed in xEdit ("Unknown 4") and is kept
    /// in `rawValue` rather than given a speculative name.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let playsOneSelection = Flags(rawValue: 0x0001)
        public static let abruptTransition = Flags(rawValue: 0x0002)
        public static let cycleTracks = Flags(rawValue: 0x0004)
        /// Only meaningful together with `cycleTracks` (UESP MUSC).
        public static let maintainTrackOrder = Flags(rawValue: 0x0008)
        public static let ducksCurrentTrack = Flags(rawValue: 0x0020)
        /// Skyrim Special Edition only; named "Unknown 6" in older games.
        public static let doesNotQueue = Flags(rawValue: 0x0040)
    }

    public let formID: FormID
    public let editorID: String?
    /// FNAM. Empty set when the field is absent or the wrong width.
    public let flags: Flags
    /// PNAM first uint16. 1 is the highest priority, 100 the lowest.
    public let priority: Int?
    /// PNAM second uint16, stored scaled by 100 (126 means 1.26 dB).
    public let duckingDecibels: Float?
    /// WNAM, seconds.
    public let fadeDuration: Float?
    /// TNAM — MUST FormIDs in record order. Null entries are kept verbatim so
    /// callers see the authored ordering; `MusicRecordStore.resolve` drops them.
    public let tracks: [FormID]

    public init(record: ESMRecord) throws {
        guard record.type == "MUSC" else {
            throw ESMError.malformed("expected MUSC record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = MusicTypeFields()
        for field in try record.fields() {
            try fields.decode(field: field)
        }
        editorID = fields.editorID
        flags = fields.flags
        priority = fields.priority
        duckingDecibels = fields.duckingDecibels
        fadeDuration = fields.fadeDuration
        tracks = fields.tracks
    }

    /// Mutable accumulator for the field loop, matching the shape used by
    /// `Cell` and `Region` so the switch stays under the lint complexity cap.
    private struct MusicTypeFields {
        var editorID: String?
        var flags: Flags = []
        var priority: Int?
        var duckingDecibels: Float?
        var fadeDuration: Float?
        var tracks: [FormID] = []

        mutating func decode(field: ESMField) throws {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FNAM":
                guard field.data.count == 4 else { return }
                flags = try Flags(rawValue: reader.readUInt32())
            case "PNAM":
                guard field.data.count == 4 else { return }
                priority = try Int(reader.readUInt16())
                duckingDecibels = try Float(reader.readUInt16()) / 100
            case "WNAM":
                guard field.data.count == 4 else { return }
                fadeDuration = try reader.readFloat32()
            case "TNAM":
                tracks = try MusicFieldReader.formIDArray(field.data)
            default:
                // MUSC carries no other fields in Skyrim SE; modder additions
                // stream past untouched.
                break
            }
        }
    }
}

nonisolated public struct MusicTrack: Sendable {
    /// CNAM. The three documented values are hashed type tags rather than a
    /// dense enumeration, so unknown tags round-trip through `unknown`.
    public enum TrackType: Equatable, Sendable {
        case palette
        case singleTrack
        case silentTrack
        case unknown(UInt32)

        public init(rawValue: UInt32) {
            switch rawValue {
            case 0x23F6_78C3: self = .palette
            case 0x6ED7_E048: self = .singleTrack
            case 0xA1A9_C4D5: self = .silentTrack
            default: self = .unknown(rawValue)
            }
        }
    }

    /// LNAM, a 12-byte struct.
    public struct LoopData: Equatable, Sendable {
        public let beginSeconds: Float
        public let endSeconds: Float
        public let count: Int
    }

    public let formID: FormID
    public let editorID: String?
    /// CNAM. nil when absent or the wrong width.
    public let trackType: TrackType?
    /// FLTV, seconds. Authored on silent and palette tracks.
    public let duration: Float?
    /// DNAM, seconds. Authored on palette tracks.
    public let fadeOut: Float?
    /// ANAM — the audio file, relative to the game data root. Raw as authored;
    /// `MusicRecordStore.canonicalMusicPath` turns it into a VFS key.
    public let trackFileName: String?
    /// BNAM — the optional finale/tail file, same path rules as `trackFileName`.
    public let finaleFileName: String?
    /// FNAM — cue points in seconds, in record order.
    public let cuePoints: [Float]
    public let loopData: LoopData?
    /// SNAM — palette children (MUST FormIDs). A null entry is a layer
    /// separator (UESP MUST), so nulls are kept verbatim.
    public let tracks: [FormID]
    /// CTDA conditions gating this track, in record order.
    public let conditions: [Condition]
    /// CITC, the authored condition count. nil when the field is absent; it can
    /// disagree with `conditions.count` if a CTDA payload was malformed.
    public let declaredConditionCount: Int?

    public init(record: ESMRecord) throws {
        guard record.type == "MUST" else {
            throw ESMError.malformed("expected MUST record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var fields = MusicTrackFields()
        for field in try record.fields() {
            try fields.decode(field: field)
        }
        editorID = fields.editorID
        trackType = fields.trackType
        duration = fields.duration
        fadeOut = fields.fadeOut
        trackFileName = fields.trackFileName
        finaleFileName = fields.finaleFileName
        cuePoints = fields.cuePoints
        loopData = fields.loopData
        tracks = fields.tracks
        conditions = fields.conditions.conditions
        declaredConditionCount = fields.conditions.declaredCount
    }

    private struct MusicTrackFields {
        var editorID: String?
        var trackType: TrackType?
        var duration: Float?
        var fadeOut: Float?
        var trackFileName: String?
        var finaleFileName: String?
        var cuePoints: [Float] = []
        var loopData: LoopData?
        var tracks: [FormID] = []
        var conditions = ConditionList()

        mutating func decode(field: ESMField) throws {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "CNAM":
                guard field.data.count == 4 else { return }
                trackType = try TrackType(rawValue: reader.readUInt32())
            case "FLTV":
                duration = try MusicFieldReader.float(field.data)
            case "DNAM":
                fadeOut = try MusicFieldReader.float(field.data)
            case "ANAM":
                trackFileName = try reader.readZString()
            case "BNAM":
                finaleFileName = try reader.readZString()
            case "FNAM":
                cuePoints = try MusicFieldReader.floatArray(field.data)
            case "LNAM":
                loopData = try MusicFieldReader.loopData(field.data)
            case "SNAM":
                tracks = try MusicFieldReader.formIDArray(field.data)
            default:
                // CITC/CTDA/CIS1/CIS2 go to the shared condition decoder; any
                // other field streams past untouched.
                try conditions.decode(field: field)
            }
        }
    }
}

/// Shared fixed-width field readers for the music records. Each one returns nil
/// on an unexpected payload width rather than shifting the read.
nonisolated private enum MusicFieldReader {
    static func float(_ data: Data) throws -> Float? {
        guard data.count == 4 else { return nil }
        var reader = BinaryReader(data)
        return try reader.readFloat32()
    }

    static func floatArray(_ data: Data) throws -> [Float] {
        guard !data.isEmpty, data.count % 4 == 0 else { return [] }
        var reader = BinaryReader(data)
        var out: [Float] = []
        out.reserveCapacity(data.count / 4)
        for _ in 0 ..< (data.count / 4) {
            try out.append(reader.readFloat32())
        }
        return out
    }

    static func formIDArray(_ data: Data) throws -> [FormID] {
        guard !data.isEmpty, data.count % 4 == 0 else { return [] }
        var reader = BinaryReader(data)
        var out: [FormID] = []
        out.reserveCapacity(data.count / 4)
        for _ in 0 ..< (data.count / 4) {
            try out.append(FormID(reader.readUInt32()))
        }
        return out
    }

    static func loopData(_ data: Data) throws -> MusicTrack.LoopData? {
        guard data.count == 12 else { return nil }
        var reader = BinaryReader(data)
        let begin = try reader.readFloat32()
        let end = try reader.readFloat32()
        let count = try Int(reader.readUInt32())
        return MusicTrack.LoopData(beginSeconds: begin, endSeconds: end, count: count)
    }
}
