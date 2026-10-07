// A shipped `.wav` or `.xwm` sound decoded and stored in CAF as ALAC. Builds no
// longer use it: ALAC decodes no faster than the shipped files. `asset-cache
// measure` and `audio aac-check` keep using it (docs/engine/asset-cache.md, "Audio").

import Foundation
import OpenSkyAssetCache
import OpenSkyFormatsAudio

nonisolated public struct CachedAudioConverter: AssetConverting {
    /// Longer sounds stream from the original file instead.
    public static let maximumSeconds: Double = 30

    public init() {}

    public var kind: AssetCacheKind {
        .audio
    }

    public var version: UInt32 {
        AssetConverterVersion.audio
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".wav") || path.hasSuffix(".xwm")
    }

    public func convert(path _: String, bytes: Data, preset _: AssetQualityPreset) throws -> Data? {
        let audio = try Self.decode(bytes)
        guard audio.frameCount > 0, audio.duration <= Self.maximumSeconds else { return nil }
        return try Self.encode(audio, format: .alac)
    }

    /// The sampling rates AAC defines (ISO/IEC 14496-3). Some vanilla sounds use
    /// 22000 Hz; those stay ALAC rather than being resampled.
    public static let aacSampleRates: Set = [
        8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000
    ]

    public static func decode(_ bytes: Data) throws -> DecodedAudio {
        if WorldAudioEngine.isWAV(bytes) {
            let file = try WAVFile(data: bytes)
            return DecodedAudio(
                sampleRate: file.format.sampleRate, channelCount: file.format.channelCount,
                samples: file.samples
            )
        }
        let file = try XWMFile(data: bytes)
        let packets = (0 ..< file.packetCount).compactMap { file.packet(at: $0) }
        return try WMADecoder.decode(
            packets: packets,
            parameters: AudioCodecParameters(xwm: file.codec)
        )
    }

    /// ExtAudioFile writes to a URL, so the encode goes through a scratch file.
    public static func encode(_ audio: DecodedAudio, format: CAFAudioFormat) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-audio-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try CAFAudioCodec.write(audio, to: url, format: format)
        return try Data(contentsOf: url)
    }
}

nonisolated extension AssetCacheDecoder where Value == DecodedAudio {
    public static var cachedAudio: Self {
        Self(kind: .audio, converterVersion: AssetConverterVersion.audio) {
            try CAFAudioCodec.read($0)
        }
    }
}
