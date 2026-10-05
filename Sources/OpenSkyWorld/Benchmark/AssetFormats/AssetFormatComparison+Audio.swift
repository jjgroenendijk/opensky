// Audio candidates: the decoded samples stored as PCM, ALAC, or AAC in a CAF
// file and decoded by AudioToolbox. The original is the shipped WAV, xWMA, or
// FUZ voice file, decoded whole by the engine's own decoders.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsAudio
import OpenSkyGameData
import OpenSkyRendering

extension AssetFormatComparison {
    func measureAudio(_ entry: AssetSampleEntry) throws -> AssetMeasurement {
        let source = try files.contents(forPath: entry.path)
        let original = try originalRow(entry, sourceBytes: source.count) {
            let (data, read) = try Self.timed { try files.contents(forPath: entry.path) }
            let (audio, decode) = try Self.timed { try Self.decodeShippedAudio(data) }
            return Sample(
                timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: 0),
                memoryBytes: audio.samples.count * MemoryLayout<Float>.size
            )
        }
        let reference = try Self.decodeShippedAudio(source)
        var rows = [original]
        for format in CAFAudioFormat.allCases {
            rows += try audioRows(format, reference: reference)
        }
        return AssetMeasurement(
            entry: entry,
            detail: "\(reference.sampleRate) Hz, \(reference.channelCount) channels, "
                + String(format: "%.1f s", reference.duration),
            candidates: rows
        )
    }

    /// AudioToolbox reads the file itself, so the whole load counts as decode.
    private func audioRows(
        _ format: CAFAudioFormat,
        reference: DecodedAudio
    ) throws -> [AssetCandidateMeasurement] {
        let url = nextScratchURL(.raw).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let (_, convertMS) = try Self.timed {
            try CAFAudioCodec.write(reference, to: url, format: format)
        }
        let decoded = try CAFAudioCodec.read(url)
        let noise = Self.signalToNoise(reference: reference.samples, candidate: decoded.samples)
        let fidelity = AssetFidelity(exact: noise == nil, signalToNoiseDB: noise)
        let disk = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let sample = try medianRun {
            let (audio, decode) = try Self.timed { try CAFAudioCodec.read(url) }
            return Sample(
                timing: AssetLoadTiming(readMS: 0, decodeMS: decode, uploadMS: 0),
                memoryBytes: audio.samples.count * MemoryLayout<Float>.size
            )
        }
        return [AssetCandidateMeasurement(
            candidate: format.rawValue, storage: .raw, path: .cpu, timing: sample.timing,
            sizes: (sample.memoryBytes, disk), fidelity: fidelity, convertMS: convertMS
        )]
    }

    /// WAV holds PCM; xWMA, alone or inside a FUZ voice file, goes through ffmpeg.
    static func decodeShippedAudio(_ data: Data) throws -> DecodedAudio {
        let audio = (try? FUZFile(data: data).audioData) ?? data
        if WorldAudioEngine.isWAV(audio) {
            let wav = try WAVFile(data: audio)
            return DecodedAudio(
                sampleRate: wav.format.sampleRate,
                channelCount: wav.format.channelCount,
                samples: wav.samples
            )
        }
        let xwm = try XWMFile(data: audio)
        return try WMADecoder.decode(
            packets: (0 ..< xwm.packetCount).compactMap(xwm.packet(at:)),
            parameters: AudioCodecParameters(xwm: xwm.codec)
        )
    }

    /// Nil when the samples are identical. Compares the common length.
    nonisolated static func signalToNoise(reference: [Float], candidate: [Float]) -> Double? {
        let count = min(reference.count, candidate.count)
        var signal = 0.0
        var noise = 0.0
        for index in 0 ..< count {
            let value = Double(reference[index])
            let error = value - Double(candidate[index])
            signal += value * value
            noise += error * error
        }
        guard noise > 0 || reference.count != candidate.count else { return nil }
        guard noise > 0 else { return TextureImageDifference.losslessPSNR }
        return 10 * log10(max(signal, .leastNonzeroMagnitude) / noise)
    }
}
