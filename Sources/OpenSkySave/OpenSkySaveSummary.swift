// The `SUMM` and `THMB` chunks: what the save and load list shows for one file,
// readable without decoding the world. See docs/formats/opensky-save.md.

import Foundation
import OpenSkyFormatsCore

/// The list row of a save: who, where, and how long.
nonisolated public struct SaveSummary: Equatable, Sendable {
    public var characterName: String
    public var level: Int
    public var raceName: String
    public var locationName: String
    /// Real seconds played across sessions, not game time.
    public var playSeconds: Double

    public init(
        characterName: String, level: Int, raceName: String, locationName: String,
        playSeconds: Double
    ) {
        self.characterName = characterName
        self.level = level
        self.raceName = raceName
        self.locationName = locationName
        self.playSeconds = playSeconds
    }
}

/// A small RGBA8 picture of the frame at save time, rows top first.
nonisolated public struct SaveThumbnail: Equatable, Sendable {
    public static let maximumSide = 512

    public let width: Int
    public let height: Int
    public let rgba: Data

    /// Nil when the size is out of range or the bytes do not fill it.
    public init?(width: Int, height: Int, rgba: Data) {
        guard
            (1 ... Self.maximumSide).contains(width), (1 ... Self.maximumSide).contains(height),
            rgba.count == width * height * 4
        else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// What the list reads from one file: header, summary, and picture.
nonisolated public struct OpenSkySaveSummaryFile: Equatable, Sendable {
    public let metadata: SaveCreationMetadata
    public let summary: SaveSummary?
    public let thumbnail: SaveThumbnail?
}

nonisolated extension OpenSkySaveFormat.ChunkTag {
    /// Character name, level, race, location, and play time for the list.
    public static let summary = "SUMM"
    /// A small picture: `UInt16` width, `UInt16` height, then RGBA8 rows.
    public static let thumbnail = "THMB"
}

nonisolated public enum OpenSkySaveSummaryCodec: Sendable {
    public static func write(_ summary: SaveSummary, into writer: inout BinaryWriter) {
        OpenSkySaveEncoder.writeChunk(tag: OpenSkySaveFormat.ChunkTag.summary, into: &writer) {
            OpenSkySaveEncoder.writeString(summary.characterName, into: &$0)
            $0.writeUInt16(UInt16(clamping: summary.level))
            OpenSkySaveEncoder.writeString(summary.raceName, into: &$0)
            OpenSkySaveEncoder.writeString(summary.locationName, into: &$0)
            $0.writeUInt64(max(0, summary.playSeconds).bitPattern)
        }
    }

    public static func write(_ thumbnail: SaveThumbnail, into writer: inout BinaryWriter) {
        OpenSkySaveEncoder.writeChunk(tag: OpenSkySaveFormat.ChunkTag.thumbnail, into: &writer) {
            $0.writeUInt16(UInt16(thumbnail.width))
            $0.writeUInt16(UInt16(thumbnail.height))
            $0.write(thumbnail.rgba)
        }
    }

    public static func decodeSummary(_ payload: Data) throws -> SaveSummary {
        var reader = SaveReader(payload)
        let name = try reader.string("SUMM character name")
        let level = try Int(reader.uint16("SUMM level"))
        let race = try reader.string("SUMM race")
        let location = try reader.string("SUMM location")
        let seconds = try Double(bitPattern: reader.uint64("SUMM play time"))
        guard seconds.isFinite, seconds >= 0 else {
            throw OpenSkySaveError.invalidValue(context: "SUMM play time is \(seconds)")
        }
        return SaveSummary(
            characterName: name, level: level, raceName: race, locationName: location,
            playSeconds: seconds
        )
    }

    public static func decodeThumbnail(_ payload: Data) throws -> SaveThumbnail {
        var reader = SaveReader(payload)
        let width = try Int(reader.uint16("THMB width"))
        let height = try Int(reader.uint16("THMB height"))
        let rgba = try reader.bytes(reader.bytesRemaining, "THMB pixels")
        guard let thumbnail = SaveThumbnail(width: width, height: height, rgba: rgba) else {
            throw OpenSkySaveError.invalidValue(
                context: "THMB is \(width)x\(height) with \(rgba.count) bytes"
            )
        }
        return thumbnail
    }

    /// Reads the header and the list chunks only. Every other chunk is skipped by
    /// its length, so a large world costs one pass over chunk headers.
    public static func readSummary(_ data: Data) throws -> OpenSkySaveSummaryFile {
        var reader = SaveReader(data)
        guard try reader.bytes(OpenSkySaveFormat.magic.count, "magic") == OpenSkySaveFormat.magic
        else { throw OpenSkySaveError.badMagic }
        let version = try reader.uint32("format version")
        guard version == OpenSkySaveFormat.currentVersion else {
            throw OpenSkySaveError.unsupportedVersion(found: version)
        }
        let metadata = try OpenSkySaveDecoder.decodeMetadata(&reader)
        _ = try OpenSkySaveDecoder.decodeFingerprint(&reader)
        var summary: SaveSummary?
        var thumbnail: SaveThumbnail?
        while !reader.isAtEnd {
            let tag = try OpenSkySaveDecoder.tagName(reader.bytes(4, "chunk tag"))
            let length = try Int(reader.uint32("chunk length"))
            guard length <= reader.bytesRemaining else {
                throw OpenSkySaveError.chunkBoundsViolation(tag: tag)
            }
            let payload = try reader.bytes(length, "chunk payload")
            switch tag {
            case OpenSkySaveFormat.ChunkTag.summary: summary = try decodeSummary(payload)
            case OpenSkySaveFormat.ChunkTag.thumbnail: thumbnail = try decodeThumbnail(payload)
            default: continue
            }
        }
        return OpenSkySaveSummaryFile(
            metadata: metadata, summary: summary, thumbnail: thumbnail
        )
    }
}
