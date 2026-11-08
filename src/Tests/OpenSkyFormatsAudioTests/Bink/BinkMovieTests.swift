// Bink 1 container framing tests over synthetic files (docs/formats/bink.md).
// Malformed input must throw `BinkMovieError`, never trap.

import Foundation
@testable import OpenSkyFormatsAudio
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite("Bink framing", .tags(.parser))
struct BinkMovieTests {
    @Test func theHeaderGivesThePictureRateAndTracks() throws {
        let movie = try BinkMovie(data: BinkFixture.file(
            tracks: [.init(id: 1, flags: 0x3000), .init(id: 0, rate: 22050, flags: 0)],
            frames: [
                .init(audioSizes: [8, 0], isKeyframe: true), .init(audioSizes: [0, 0])
            ]
        ))
        #expect(movie.width == 64)
        #expect(movie.height == 32)
        #expect(movie.revision == UInt8(ascii: "i"))
        #expect(abs(movie.framesPerSecond - 23.976) < 0.001)
        #expect(movie.audioTracks == [
            BinkAudioTrack(id: 1, sampleRate: 48000, channelCount: 2, usesDCT: true),
            BinkAudioTrack(id: 0, sampleRate: 22050, channelCount: 1, usesDCT: false)
        ])
        #expect(movie.frames.map(\.isKeyframe) == [true, false])
    }

    @Test func aFrameSplitsIntoAudioAndVideoPackets() throws {
        let data = BinkFixture.file(
            tracks: [.init(id: 0)],
            frames: [.init(audioSizes: [12], videoSize: 5), .init(audioSizes: [2], videoSize: 3)]
        )
        let movie = try BinkMovie(data: data)
        let first = try movie.packets(ofFrame: 0, in: data)
        #expect(first.audio == [BinkFixture.packet(12, tag: 0x40)])
        #expect(first.video == BinkFixture.packet(5, tag: 0) + Data([0]))
        // A packet under four bytes cannot hold its sample count, so it carries no sound.
        let second = try movie.packets(ofFrame: 1, in: data)
        #expect(second.audio == [nil])
        #expect(second.video == BinkFixture.packet(3, tag: 1) + Data([0]))
    }

    @Test func revisionKSkipsItsExtraField() throws {
        let data = BinkFixture.file(revision: "k", frames: [.init(videoSize: 4)])
        let movie = try BinkMovie(data: data)
        #expect(try movie.packets(ofFrame: 0, in: data).video == BinkFixture.packet(4, tag: 0))
    }

    @Test func binkTwoIsDeclined() {
        #expect(throws: BinkMovieError.unsupported("Bink 2 video")) {
            try BinkMovie(data: BinkFixture.file(revision: "g", signature: "KB2"))
        }
    }

    @Test func badHeadersThrow() {
        let cases = [
            BinkFixture.file(signature: "XYZ"),
            BinkFixture.file(width: 0),
            BinkFixture.file(rate: (24, 0)),
            BinkFixture.file(frames: []),
            Data(BinkFixture.file().prefix(30))
        ]
        for data in cases {
            #expect(throws: BinkMovieError.self) { try BinkMovie(data: data) }
        }
    }

    @Test func anAudioPacketLargerThanItsFrameThrows() throws {
        var data = BinkFixture.file(tracks: [.init(id: 0)], frames: [.init(audioSizes: [4])])
        let movie = try BinkMovie(data: data)
        let sizeOffset = movie.frames[0].offset
        data.replaceSubrange(sizeOffset ..< sizeOffset + 4, with: [0xFF, 0, 0, 0])
        #expect(throws: BinkMovieError.self) { try movie.packets(ofFrame: 0, in: data) }
        #expect(throws: BinkMovieError.self) { try movie.packets(ofFrame: 5, in: data) }
    }
}
