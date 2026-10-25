// Connects the sound director to the load-order SOPM and REVB records. The
// sound and acoustic-space stores hold raw links into the base plugin.
// See docs/formats/sound-output-reverb.md.

import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData

extension WorldAudioSoundDirector {
    /// The plugin the sound and acoustic-space stores are built from.
    public static let soundPlugin = "Skyrim.esm"

    static func outputModels(_ records: EffectRecordStore) -> (FormID) -> OutputModelProfile? {
        { id in
            records.outputModels.resolve(id, fromPlugin: soundPlugin)
                .flatMap { OutputModelProfile(model: $0.record) }
        }
    }

    static func reverbs(_ records: EffectRecordStore) -> (FormID) -> ReverbParameters? {
        { id in records.reverbs.resolve(id, fromPlugin: soundPlugin)?.record }
    }
}
