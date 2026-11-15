// Records the reference game's own sound to a WAV file through ScreenCaptureKit, so a check
// can compare when the game plays a sound. It needs the Screen Recording permission, like a
// window capture, and records only the Wine processes, not OpenSky or other apps.

import AVFoundation
import CoreMedia
public import Foundation
import OpenSkyFormatsCore
import ScreenCaptureKit
import Synchronization

nonisolated public enum ReferenceAudioCaptureError: Error, Equatable, Sendable, LocalizedError {
    case noGame
    case noSound

    public var errorDescription: String? {
        switch self {
        case .noGame: "No reference game window is on screen. Start the reference game first."
        case .noSound: "The capture received no sound. Check the Screen Recording permission."
        }
    }
}

nonisolated public enum ReferenceAudioCapture {
    static let sampleRate = 48000

    /// Records `seconds` of the reference game's sound into a 48 kHz stereo WAV at `url`.
    public static func record(seconds: Double, to url: URL) async throws {
        guard let window = ReferenceWindowCapture.window(expected: nil) else {
            throw ReferenceAudioCaptureError.noGame
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        let wine = content.applications.filter {
            $0.processID == window.ownerPID || isWine($0.applicationName)
        }
        guard let display = content.displays.first, !wine.isEmpty else {
            throw ReferenceAudioCaptureError.noGame
        }
        let filter = SCContentFilter(display: display, including: wine, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = sampleRate
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        // The stream always carries pictures; the smallest, slowest ones cost least.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let writer = try ReferenceAudioWriter(url: url, sampleRate: Double(sampleRate))
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: nil)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        guard writer.finish() > 0 else {
            throw ReferenceAudioCaptureError.noSound
        }
    }

    static func isWine(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ReferenceWindow.ownerHints.contains { lowered.contains($0) }
    }
}

/// Appends each audio buffer the stream delivers to the file, on the stream's own queue.
nonisolated final class ReferenceAudioWriter: NSObject, SCStreamOutput, Sendable {
    private struct Output: ~Copyable {
        let file: AVAudioFile
        let format: AVAudioFormat
        var frames: AVAudioFramePosition = 0
    }

    private let output: Mutex<Output>

    init(url: URL, sampleRate: Double) throws {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2,
                interleaved: false
            )
        else { throw ReferenceAudioCaptureError.noSound }
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        output = Mutex(Output(file: file, format: format))
    }

    func stream(
        _: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }
        let count = AVAudioFrameCount(sampleBuffer.numSamples)
        guard count > 0 else { return }
        output.withLock { output in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: output.format, frameCapacity: count)
            else { return }
            buffer.frameLength = count
            let status = unsafe CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList
            )
            guard status == noErr, attempt({ try output.file.write(from: buffer) }) != nil
            else { return }
            output.frames += AVAudioFramePosition(count)
        }
    }

    /// The number of frames written so far.
    func finish() -> AVAudioFramePosition {
        output.withLock { $0.frames }
    }
}
