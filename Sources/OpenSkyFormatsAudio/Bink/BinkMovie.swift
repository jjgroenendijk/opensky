// `.bik` Bink 1 movie framing: the header, the audio track list, the frame index,
// and the packets of one frame. Decoding the packets is libavcodec's job.
// Layout and sources: docs/formats/bink.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum BinkMovieError: Error, Equatable, Sendable {
    /// Input violates the documented layout.
    case malformed(String)
    /// Structurally valid, but a variant OpenSky declines, such as Bink 2.
    case unsupported(String)
}

nonisolated public struct BinkAudioTrack: Equatable, Sendable {
    public let id: UInt32
    public let sampleRate: Int
    public let channelCount: Int
    /// Flags bit 12: the DCT codec, else the RDFT one.
    public let usesDCT: Bool

    public init(id: UInt32, sampleRate: Int, channelCount: Int, usesDCT: Bool) {
        self.id = id
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.usesDCT = usesDCT
    }
}

/// One frame's bytes in the file.
nonisolated public struct BinkFrameRange: Equatable, Sendable {
    public let offset: Int
    public let size: Int
    public let isKeyframe: Bool
}

/// One frame's packets: an audio packet per track, nil when the track has none in this
/// frame, then the video packet.
nonisolated public struct BinkFramePackets: Equatable, Sendable {
    public let audio: [Data?]
    public let video: Data
}

nonisolated public struct BinkMovie: Sendable {
    private enum Layout {
        static let signature: UInt32 = 0x4B4942 // "BIK"
        static let secondVersionSignature: UInt32 = 0x32424B // "KB2"
        static let maximumFrames = 1_000_000
        static let maximumDimension = 32767
        static let maximumAudioTracks = 256
        static let stereoFlag: UInt16 = 1 << 13
        static let dctFlag: UInt16 = 1 << 12
    }

    /// The first four bytes, `BIK` and the revision letter. The video decoder reads it.
    public let codecTag: UInt32
    public let width: Int
    public let height: Int
    public let frameRateNumerator: UInt32
    public let frameRateDenominator: UInt32
    /// The video decoder reads these as its 4-byte private data.
    public let videoFlags: UInt32
    public let audioTracks: [BinkAudioTrack]
    public let frames: [BinkFrameRange]

    public var revision: UInt8 {
        UInt8(codecTag >> 24)
    }

    public var framesPerSecond: Double {
        Double(frameRateNumerator) / Double(frameRateDenominator)
    }

    public var duration: Double {
        Double(frames.count) / framesPerSecond
    }

    public init(data: Data) throws {
        var reader = BinaryReader(data)
        do {
            codecTag = try reader.readUInt32()
            let signature = codecTag & 0xFFFFFF
            if signature == Layout.secondVersionSignature {
                throw BinkMovieError.unsupported("Bink 2 video")
            }
            guard signature == Layout.signature else {
                throw BinkMovieError.malformed("signature is not BIK")
            }
            // The size field counts the bytes after the first eight.
            let fileSize = try Int(reader.readUInt32()) + 8
            let frameCount = try Int(reader.readUInt32())
            reader.skip(8) // largest frame size, frame count again
            width = try Int(reader.readUInt32())
            height = try Int(reader.readUInt32())
            frameRateNumerator = try reader.readUInt32()
            frameRateDenominator = try reader.readUInt32()
            videoFlags = try reader.readUInt32()
            let trackCount = try Int(reader.readUInt32())
            try Self.validate(
                frameCount: frameCount, trackCount: trackCount,
                size: (width, height), rate: (frameRateNumerator, frameRateDenominator)
            )
            if UInt8(codecTag >> 24) == UInt8(ascii: "k") {
                reader.skip(4) // a field revision k adds; its meaning is unknown
            }
            audioTracks = try Self.readTracks(count: trackCount, reader: &reader)
            frames = try Self.readFrameIndex(
                count: frameCount, fileEnd: min(fileSize, data.count), reader: &reader
            )
        } catch let error as BinaryReaderError {
            throw BinkMovieError.malformed("header ends early: \(error)")
        }
    }

    /// The audio and video packets of frame `index`.
    public func packets(ofFrame index: Int, in data: Data) throws -> BinkFramePackets {
        guard frames.indices.contains(index) else {
            throw BinkMovieError.malformed("frame \(index) is outside 0..<\(frames.count)")
        }
        let range = frames[index]
        guard range.offset + range.size <= data.count else {
            throw BinkMovieError.malformed("frame \(index) runs past the end of the file")
        }
        var reader = BinaryReader(data, offset: range.offset)
        var remaining = range.size
        var audio: [Data?] = []
        do {
            for _ in audioTracks {
                let size = try Int(reader.readUInt32())
                guard size <= remaining - 4 else {
                    throw BinkMovieError.malformed("frame \(index) audio packet is too large")
                }
                remaining -= 4 + size
                // A packet starts with its decoded size, so one under 4 bytes holds no sound.
                if size >= 4 {
                    try audio.append(reader.read(count: size))
                } else {
                    reader.skip(size)
                    audio.append(nil)
                }
            }
            return try BinkFramePackets(audio: audio, video: reader.read(count: remaining))
        } catch let error as BinaryReaderError {
            throw BinkMovieError.malformed("frame \(index) ends early: \(error)")
        }
    }

    private static func validate(
        frameCount: Int, trackCount: Int, size: (Int, Int), rate: (UInt32, UInt32)
    ) throws {
        guard (1 ... Layout.maximumFrames).contains(frameCount) else {
            throw BinkMovieError.malformed("frame count \(frameCount)")
        }
        let dimensions = 1 ... Layout.maximumDimension
        guard dimensions.contains(size.0), dimensions.contains(size.1) else {
            throw BinkMovieError.malformed("picture size \(size.0) x \(size.1)")
        }
        guard rate.0 > 0, rate.1 > 0 else {
            throw BinkMovieError.malformed("frame rate \(rate.0)/\(rate.1)")
        }
        guard trackCount <= Layout.maximumAudioTracks else {
            throw BinkMovieError.malformed("\(trackCount) audio tracks")
        }
    }

    /// Three tables, one entry per track each: the largest decoded packet, rate and
    /// flags, then the track ID.
    private static func readTracks(
        count: Int, reader: inout BinaryReader
    ) throws -> [BinkAudioTrack] {
        reader.skip(4 * count)
        var formats: [(rate: UInt16, flags: UInt16)] = []
        for _ in 0 ..< count {
            try formats.append((reader.readUInt16(), reader.readUInt16()))
        }
        return try formats.map { format in
            try BinkAudioTrack(
                id: reader.readUInt32(),
                sampleRate: Int(format.rate),
                channelCount: format.flags & Layout.stereoFlag != 0 ? 2 : 1,
                usesDCT: format.flags & Layout.dctFlag != 0
            )
        }
    }

    /// Bit 0 of an offset marks a keyframe. The last frame ends at the file size.
    private static func readFrameIndex(
        count: Int, fileEnd: Int, reader: inout BinaryReader
    ) throws -> [BinkFrameRange] {
        let entries = try (0 ..< count).map { _ in try reader.readUInt32() }
        let indexEnd = reader.offset
        var frames: [BinkFrameRange] = []
        frames.reserveCapacity(count)
        for (index, entry) in entries.enumerated() {
            let offset = Int(entry & ~1)
            let end = index + 1 < count ? Int(entries[index + 1] & ~1) : fileEnd
            guard offset >= indexEnd, end > offset, end <= fileEnd else {
                throw BinkMovieError.malformed("frame \(index) has offsets \(offset)..<\(end)")
            }
            frames.append(BinkFrameRange(
                offset: offset, size: end - offset, isKeyframe: entry & 1 != 0
            ))
        }
        return frames
    }
}
