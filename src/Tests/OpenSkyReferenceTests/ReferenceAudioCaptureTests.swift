// Recording the reference game's sound: which apps count as the game, the messages a
// failed recording gives, and the WAV writer before any sound arrives.

import AVFoundation
import CoreMedia
import Foundation
@testable import OpenSkyReference
import ScreenCaptureKit
import Testing

struct ReferenceAudioCaptureTests {
    @Test func onlyWineAndSkyrimAppsAreRecorded() {
        #expect(ReferenceAudioCapture.isWine("wine64-preloader"))
        #expect(ReferenceAudioCapture.isWine("SkyrimSE.exe"))
        #expect(!ReferenceAudioCapture.isWine("Music"))
    }

    @Test func eachFailureSaysWhatToCheck() {
        #expect(ReferenceAudioCaptureError.noGame.errorDescription?.contains("Start") == true)
        #expect(ReferenceAudioCaptureError.noSound.errorDescription?.contains("Screen") == true)
    }

    @Test func aWriterWithNoSoundHasWrittenNothing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reference-audio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ReferenceAudioWriter(url: url, sampleRate: 48000)
        #expect(writer.finish() == 0)
    }

    @Test func eachSoundBufferAddsItsFrames() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reference-audio-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try ReferenceAudioWriter(url: url, sampleRate: 48000)
        let stream = SCStream(
            filter: SCContentFilter(), configuration: SCStreamConfiguration(), delegate: nil
        )
        let sound = try Self.silence(frames: 64)
        writer.stream(stream, didOutputSampleBuffer: sound, of: .screen)
        #expect(writer.finish() == 0, "a picture buffer is not sound")
        writer.stream(stream, didOutputSampleBuffer: sound, of: .audio)
        #expect(writer.finish() == 64)
    }

    /// Stereo 48 kHz float silence, laid out as the capture stream delivers it.
    private static func silence(frames: Int) throws -> CMSampleBuffer {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false
        ))
        let pcm = try #require(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)
        ))
        pcm.frameLength = AVAudioFrameCount(frames)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var made: CMSampleBuffer?
        let created = unsafe CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: format.formatDescription, sampleCount: frames,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
            sampleSizeArray: nil, sampleBufferOut: &made
        )
        let sample = try #require(made)
        let filled = unsafe CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            bufferList: pcm.audioBufferList
        )
        #expect(created == noErr && filled == noErr)
        return sample
    }

    @Test(.enabled(if: ReferenceWindowCapture.window(expected: nil) == nil))
    func withoutTheGameARecordingFailsAtOnce() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("unused.wav")
        await #expect(throws: ReferenceAudioCaptureError.noGame) {
            try await ReferenceAudioCapture.record(seconds: 1, to: url)
        }
    }
}
