// The AAC check for the audio cache: encode a sound as the cache would, decode
// it, and measure it against the original. See docs/engine/asset-cache.md, "Audio".

import Foundation
import OpenSkyAssetCache

nonisolated public enum AACTransparency {
    public static func measure(_ audio: DecodedAudio) throws -> SpectralDistortion {
        let aac = try CAFAudioCodec.read(CachedAudioConverter.encode(audio, format: .aac))
        return SpectralDistortionMeter.measure(reference: audio, candidate: aac)
    }

    /// Evenly spaced paths of each category, from the sorted list, so a rerun
    /// picks the same sample.
    public static func sample(
        paths: [String], perCategory: Int
    ) -> [AssetSoundCategory: [String]] {
        let grouped = Dictionary(grouping: paths.sorted()) { AssetSoundCategory(path: $0) }
        return grouped.mapValues { group in
            guard group.count > perCategory, perCategory > 0 else { return group }
            return (0 ..< perCategory).map { group[$0 * group.count / perCategory] }
        }
    }
}
