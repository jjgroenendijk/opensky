// MUSC music types group the MUST music tracks a playlist may choose from and
// carry the selection/transition policy (priority, ducking, fade). MUST music
// tracks name the audio file to stream plus its loop and finale data.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/MUSC"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUSC
//   UESP "Skyrim Mod:Mod File Format/MUST"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUST
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas (MUSC lines 7074-7092,
//     MUST lines 7203-7226)
// Layout documented in docs/formats/music.md.

import Foundation

nonisolated struct MusicType {
    /// FNAM bitfield. Bit 0x10 is unnamed in xEdit ("Unknown 4") and is kept
    /// in `rawValue` rather than given a speculative name.
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt32

        static let playsOneSelection = Flags(rawValue: 0x0001)
        static let abruptTransition = Flags(rawValue: 0x0002)
        static let cycleTracks = Flags(rawValue: 0x0004)
        /// Only meaningful together with `cycleTracks` (UESP MUSC).
        static let maintainTrackOrder = Flags(rawValue: 0x0008)
        static let ducksCurrentTrack = Flags(rawValue: 0x0020)
        /// Skyrim Special Edition only; named "Unknown 6" in older games.
        static let doesNotQueue = Flags(rawValue: 0x0040)
    }

    let formID: FormID
    let editorID: String?
    /// FNAM. Empty set when the field is absent or the wrong width.
    let flags: Flags
    /// PNAM first uint16. 1 is the highest priority, 100 the lowest.
    let priority: Int?
    /// PNAM second uint16, stored scaled by 100 (126 means 1.26 dB).
    let duckingDecibels: Float?
    /// WNAM, seconds.
    let fadeDuration: Float?
    /// TNAM — MUST FormIDs in record order. Null entries are kept verbatim so
    /// callers see the authored ordering; `MusicRecordStore.resolve` drops them.
    let tracks: [FormID]

    init(record: ESMRecord) throws {
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

nonisolated struct MusicTrack {
    /// CNAM. The three documented values are hashed type tags rather than a
    /// dense enumeration, so unknown tags round-trip through `unknown`.
    enum TrackType: Equatable {
        case palette
        case singleTrack
        case silentTrack
        case unknown(UInt32)

        init(rawValue: UInt32) {
            switch rawValue {
            case 0x23F6_78C3: self = .palette
            case 0x6ED7_E048: self = .singleTrack
            case 0xA1A9_C4D5: self = .silentTrack
            default: self = .unknown(rawValue)
            }
        }
    }

    /// LNAM, a 12-byte struct.
    struct LoopData: Equatable {
        let beginSeconds: Float
        let endSeconds: Float
        let count: Int
    }

    let formID: FormID
    let editorID: String?
    /// CNAM. nil when absent or the wrong width.
    let trackType: TrackType?
    /// FLTV, seconds. Authored on silent and palette tracks.
    let duration: Float?
    /// DNAM, seconds. Authored on palette tracks.
    let fadeOut: Float?
    /// ANAM — the audio file, relative to the game data root. Raw as authored;
    /// `MusicRecordStore.canonicalMusicPath` turns it into a VFS key.
    let trackFileName: String?
    /// BNAM — the optional finale/tail file, same path rules as `trackFileName`.
    let finaleFileName: String?
    /// FNAM — cue points in seconds, in record order.
    let cuePoints: [Float]
    let loopData: LoopData?
    /// SNAM — palette children (MUST FormIDs). A null entry is a layer
    /// separator (UESP MUST), so nulls are kept verbatim.
    let tracks: [FormID]

    init(record: ESMRecord) throws {
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
                // CITC/CTDA conditions are not decoded: OpenSky has no
                // condition evaluator yet (docs/formats/music.md).
                break
            }
        }
    }
}

/// Shared fixed-width field readers for the music records. Each one returns nil
/// on an unexpected payload width rather than shifting the read.
private enum MusicFieldReader {
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
