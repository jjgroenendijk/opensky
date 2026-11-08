// The player's skin tone: the race default for a face without a skin tone layer,
// and the body colour the layer gives at its strength.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import simd
import Testing

struct PlayerSkinToneTests {
    private static func skinMask() -> RaceTintMask {
        var mask = RaceTintMask()
        (mask.index, mask.maskType) = (4, PlayerAppearanceOverride.skinToneMaskType)
        mask.presetDefault = FormID(0x21)
        mask.presets = [
            RaceTintPreset(color: FormID(0x20), defaultValue: 1),
            RaceTintPreset(color: FormID(0x21), defaultValue: 50)
        ]
        return mask
    }

    private static func override(tints: [PlayerAppearanceTint]) -> PlayerAppearanceOverride {
        var override = PlayerAppearanceOverride(
            race: FormID(0xA1), isFemale: false, headParts: [], hairColor: nil
        )
        override.tints = tints
        return override
    }

    /// Vanilla `QNAM` values: Khajiit preset 10 has black at 0.5 and stores 63.
    @Test func theBodyToneMovesFromGreyToTheLayerByItsStrength() {
        let black = PlayerAppearanceOverride.bodySkinTone(layer: [0, 0, 0, 0], strength: 0.5)
        #expect(abs(black.x * 255 - 63.5) < 0.01)
        let full = PlayerAppearanceOverride.bodySkinTone(layer: [198, 176, 168, 0], strength: 1)
        #expect(simd_distance(full * 255, SIMD3(198, 176, 168)) < 0.001)
        let none = PlayerAppearanceOverride.bodySkinTone(layer: [255, 0, 0, 0], strength: 0)
        #expect(none == SIMD3(repeating: 127) / 255)
    }

    @Test func aFaceWithoutSkinToneTakesTheTINDPresetFirst() {
        let lips = PlayerAppearanceTint(maskIndex: 9, color: [80, 9, 1, 0], strength: 1)
        var face = Self.override(tints: [lips])
        face.addDefaultSkinTone(masks: [Self.skinMask()]) { id in
            id == FormID(0x21) ? [128, 128, 0, 0] : [10, 10, 10, 0]
        }
        let skin = PlayerAppearanceTint(maskIndex: 4, color: [128, 128, 0, 0], strength: 0.5)
        #expect(face.tints == [skin, lips])
        let tone = face.skinToneLayerColour(masks: [Self.skinMask()]) ?? .zero
        #expect(simd_distance(tone * 255, SIMD3(127.5, 127.5, 63.5)) < 0.001)
    }

    @Test func aFaceWithItsOwnSkinToneKeepsIt() {
        let own = PlayerAppearanceTint(maskIndex: 4, color: [90, 60, 40, 0], strength: 1)
        var face = Self.override(tints: [own])
        face.addDefaultSkinTone(masks: [Self.skinMask()]) { _ in [128, 128, 0, 0] }
        #expect(face.tints == [own])
    }
}
