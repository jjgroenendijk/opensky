// Synthetic Bink 1 container builder. Packets are counter bytes, not real codec data,
// so a test checks the framing only. Layout: docs/formats/bink.md.

import Foundation

public enum BinkFixture: Sendable {
    /// One audio track: its ID, rate, and the flags word (bit 13 stereo, bit 12 DCT).
    public struct Track: Sendable {
        public let id: UInt32
        public let rate: UInt16
        public let flags: UInt16

        public init(id: UInt32, rate: UInt16 = 48000, flags: UInt16 = 0x3000) {
            self.id = id
            self.rate = rate
            self.flags = flags
        }
    }

    /// One frame: an audio packet size per track (0 for none), then the video size.
    public struct Frame: Sendable {
        public let audioSizes: [Int]
        public let videoSize: Int
        public let isKeyframe: Bool

        var unpaddedSize: Int {
            audioSizes.reduce(videoSize) { $0 + 4 + $1 }
        }

        public init(audioSizes: [Int] = [], videoSize: Int = 8, isKeyframe: Bool = false) {
            self.audioSizes = audioSizes
            self.videoSize = videoSize
            self.isKeyframe = isKeyframe
        }
    }

    public static func packet(_ size: Int, tag: UInt8) -> Data {
        Data((0 ..< size).map { UInt8(truncatingIfNeeded: $0) &+ tag })
    }

    public static func file(
        revision: Character = "i",
        signature: String = "BIK",
        width: UInt32 = 64,
        height: UInt32 = 32,
        rate: (UInt32, UInt32) = (24000, 1001),
        tracks: [Track] = [],
        frames: [Frame] = [Frame(isKeyframe: true), Frame()]
    ) -> Data {
        var header = Data(signature.utf8)
        header.append(revision.asciiValue ?? 0)
        var body = Data()
        for (index, frame) in frames.enumerated() {
            for (track, size) in frame.audioSizes.enumerated() {
                body.appendLittleEndian(UInt32(size))
                body.append(packet(size, tag: UInt8(truncatingIfNeeded: 0x40 + track)))
            }
            body.append(packet(frame.videoSize, tag: UInt8(truncatingIfNeeded: index)))
            body.append(Data(count: frameSize(frame) - frame.unpaddedSize))
        }
        let extra = revision == "k" ? 4 : 0
        // The index holds one entry past the last frame: the end of the file.
        let headerSize = 44 + extra + 12 * tracks.count + 4 * (frames.count + 1)
        var fields = Data()
        fields.appendLittleEndian(UInt32(headerSize + body.count - 8))
        fields.appendLittleEndian(UInt32(frames.count))
        fields.appendLittleEndian(UInt32(frames.map(frameSize).max() ?? 0))
        fields.appendLittleEndian(UInt32(frames.count))
        for value in [width, height, rate.0, rate.1, 0, UInt32(tracks.count)] {
            fields.appendLittleEndian(value)
        }
        fields.append(Data(count: extra))
        for _ in tracks {
            fields.appendLittleEndian(UInt32(4096))
        }
        for track in tracks {
            fields.appendLittleEndian(track.rate)
            fields.appendLittleEndian(track.flags)
        }
        for track in tracks {
            fields.appendLittleEndian(track.id)
        }
        var offset = headerSize
        for frame in frames {
            fields.appendLittleEndian(UInt32(offset) | (frame.isKeyframe ? 1 : 0))
            offset += frameSize(frame)
        }
        fields.appendLittleEndian(UInt32(offset))
        return header + fields + body
    }

    /// Bit 0 of an index entry is the keyframe flag, so offsets stay even: an odd frame
    /// ends with a pad byte, which the reader sees as part of the video packet.
    private static func frameSize(_ frame: Frame) -> Int {
        (frame.unpaddedSize + 1) & ~1
    }
}

extension Data {
    fileprivate mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
