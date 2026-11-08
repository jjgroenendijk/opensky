// The sound category mix over a synthetic SNCT tree shaped like the vanilla one.
// See docs/engine/sound-mix.md.

import OpenSkyAudio
import OpenSkyFormatsESM
import Testing

struct SoundCategoryMixTests {
    private static let master = FormID(0x1)
    private static let pausedFade = FormID(0x2)
    private static let pausedNow = FormID(0x3)
    private static let dialogueFade = FormID(0x4)
    private static let music = FormID(0x5)
    private static let submerged = FormID(0x6)
    private static let voice = FormID(0x7)

    private static func mix() -> SoundCategoryMix {
        let nodes = [
            SoundCategory(
                formID: master,
                editorID: "Master",
                parent: nil,
                staticVolumeMultiplier: 0.9
            ),
            SoundCategory(formID: dialogueFade, editorID: "SFXFade", parent: master),
            SoundCategory(formID: pausedFade, editorID: "PausedFade", parent: dialogueFade),
            SoundCategory(formID: pausedNow, editorID: "PausedNow", parent: master),
            SoundCategory(formID: voice, editorID: "Voice", parent: pausedNow),
            SoundCategory(
                formID: music,
                editorID: "Music",
                parent: master,
                staticVolumeMultiplier: 0.7
            ),
            SoundCategory(
                formID: submerged, editorID: "Submerged", flags: .muteWhenSubmerged,
                parent: pausedFade
            )
        ]
        return SoundCategoryMix(
            categories: Dictionary(uniqueKeysWithValues: nodes.map { ($0.formID.rawValue, $0) }),
            roles: [
                .pausedDuringMenuFade: pausedFade, .pausedDuringMenuImmediate: pausedNow,
                .fadesInDialogue: dialogueFade, .music: music
            ]
        )
    }

    @Test func staticVolumesMultiplyDownTheChain() {
        let level = Self.mix().level(of: Self.music)
        #expect(abs(level.gain - 0.63) < 0.0001)
        #expect(!level.paused)
        #expect(Self.mix().level(of: nil).gain == 1)
    }

    @Test func aMenuFadesThenPausesTheFadeCategory() {
        var mix = Self.mix()
        mix.advance(SoundMixInputs(menuMode: true), seconds: 1.5)
        #expect(abs(mix.level(of: Self.pausedFade).gain - 0.45) < 0.0001)
        #expect(!mix.level(of: Self.pausedFade).paused)
        #expect(mix.level(of: Self.voice).paused)
        mix.advance(SoundMixInputs(menuMode: true), seconds: 2)
        #expect(mix.level(of: Self.pausedFade).paused)
        mix.advance(SoundMixInputs(), seconds: 0.5)
        #expect(mix.menuLevel == 0.5)
        #expect(!mix.level(of: Self.voice).paused)
    }

    @Test func dialogueDucksMusicAndTheFadeCategory() {
        var mix = Self.mix()
        mix.advance(SoundMixInputs(dialogue: true), seconds: 60)
        #expect(mix.musicLevel == SoundCategoryMix.musicDuckLevel)
        #expect(mix.dialogueLevel == SoundCategoryMix.dialogueDuckLevel)
        #expect(
            abs(mix.level(of: Self.pausedFade).gain - 0.9 * SoundCategoryMix.dialogueDuckLevel) <
                0.0001
        )
        #expect(mix.level(of: Self.voice).gain == 0.9)
        mix.advance(SoundMixInputs(), seconds: 4)
        #expect(mix.musicLevel > SoundCategoryMix.musicDuckLevel)
        #expect(mix.musicLevel < 1)
    }

    @Test func underWaterMutesTheFlaggedCategory() {
        var mix = Self.mix()
        mix.advance(SoundMixInputs(submerged: true), seconds: 0)
        #expect(mix.level(of: Self.submerged).gain == 0)
        #expect(mix.level(of: Self.pausedFade).gain > 0)
    }

    @Test func theINISecondsSetTheRamps() {
        var mix = Self.mix()
        mix.timings.menuFadeOutSeconds = 0
        mix.advance(SoundMixInputs(menuMode: true), seconds: 0.01)
        #expect(mix.menuLevel == 0)
    }
}
