// Applies the sound category mix to the playing sources: their level, and the pause a menu
// or a loading screen holds them in. The rules are in `SoundCategoryMix`
// (docs/engine/sound-mix.md).

import AVFAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM

extension WorldAudioEngine {
    /// The mix's level for `source`; full level without a mix.
    func mixLevel(of source: ActiveAudioSource) -> SoundCategoryLevel {
        guard let soundMix else { return SoundCategoryLevel(gain: 1, paused: false) }
        return soundMix.level(of: source.soundCategory ?? mixCategory(for: source.category))
    }

    /// Steps the mix and brings every source to its new level, pausing or resuming it.
    public func advanceSoundMix(_ inputs: SoundMixInputs, seconds: Float) {
        guard soundMix != nil else { return }
        soundMix?.advance(inputs, seconds: seconds)
        for source in sources {
            let level = mixLevel(of: source)
            if level.paused, !source.mixPaused {
                source.node.pause()
                source.mixPaused = true
            } else if !level.paused, source.mixPaused {
                source.node.play()
                source.mixPaused = false
            }
            applyVolume(to: source)
        }
    }

    /// The category of a voice line: the conversation's speaker, or any other voice.
    public func voiceCategory(conversation: Bool) -> FormID? {
        soundMix?.roles[conversation ? .dialogueVoice : .nonDialogueVoice]
    }

    /// The category a sound without a descriptor takes, such as a music track.
    private func mixCategory(for category: AudioCategory) -> FormID? {
        switch category {
        case .music: soundMix?.roles[.music]
        case .voice: soundMix?.roles[.nonDialogueVoice]
        case .effects, .footsteps: soundMix?.category(editorID: category.soundCategoryEditorID)
        }
    }
}
