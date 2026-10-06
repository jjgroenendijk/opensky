// The audio cache converter: a shipped `.wav` or `.xwm` sound decoded and stored
// as ALAC in CAF, which macOS decodes natively, so a cached play needs no ffmpeg.
// Long files (music, ambience) keep streaming from the original, because a
// cached file is decoded whole. See docs/engine/asset-cache.md, "Audio".

import Foundation
import OpenSkyAssetCache
import OpenSkyFormatsAudio

nonisolated public struct ALACAudioConverter: AssetConverting {
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
        return try Self.encodeALAC(audio)
    }

    static func decode(_ bytes: Data) throws -> DecodedAudio {
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
    public static func encodeALAC(_ audio: DecodedAudio) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-alac-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try CAFAudioCodec.write(audio, to: url, format: .alac)
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
