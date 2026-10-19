// The race menu's choice rows: head parts with a "none" choice, hair colour,
// complexion, and war paint with its own colour row.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
@testable import OpenSkyMenus
import Testing

struct RaceMenuValuesTests {
    private static let identity = PlayerIdentityState(
        race: FormID(0x13746), isFemale: false, name: "Prisoner"
    )
    private static let red = RaceMenuColor(formID: FormID(0x10), color: [200, 0, 0, 255])
    private static let blue = RaceMenuColor(
        formID: FormID(0x11), color: [0, 0, 200, 255], strength: 0.5
    )

    private static func model() -> RaceMenuModel {
        let options = RaceMenuOptions(
            headParts: [.facialHair: [FormID(0xB1), FormID(0xB2)], .hair: [FormID(0xA1)]],
            hairColors: [red, blue],
            tintMasks: [
                RaceMenuTintMask(index: 30, type: RaceMenuModel.paintType, colors: [red, blue]),
                RaceMenuTintMask(index: 31, type: RaceMenuModel.paintType, colors: [red])
            ],
            complexions: [FormID(0xC1), FormID(0xC2)]
        )
        return RaceMenuModel(identity: identity, races: [], limited: false, options: options)
    }

    @Test func anOptionalPartCountsNoneAsZero() {
        var model = Self.model()
        #expect(model.range(.headPart(.facialHair))?.bounds == 0 ... 2)
        #expect(model.range(.headPart(.hair))?.bounds == 0 ... 0, "hair has no none choice")
        model.set(.headPart(.facialHair), to: 2)
        #expect(model.identity.face.headParts == [FormID(0xB2)])
        model.step(.headPart(.facialHair), by: -1)
        #expect(model.identity.face.headParts == [FormID(0xB1)], "the old beard is replaced")
        model.set(.headPart(.facialHair), to: 0)
        #expect(model.identity.face.headParts.isEmpty)
    }

    @Test func hairColourAndComplexionPickFromTheRace() {
        var model = Self.model()
        model.set(.hairColor, to: 1)
        #expect(model.identity.face.hairColor == FormID(0x11))
        model.set(.complexion, to: 2)
        #expect(model.identity.face.faceTexture == FormID(0xC2))
        #expect(model.position(.complexion) == 2)
        model.set(.complexion, to: 0)
        #expect(model.identity.face.faceTexture == nil)
    }

    @Test func warPaintPicksAMaskThenItsColour() {
        var model = Self.model()
        let paint = RaceMenuModel.paintType
        #expect(model.position(.tintMask(paint)) == 0, "no paint at first")
        model.set(.tintMask(paint), to: 1)
        #expect(model.identity.face.tints.map(\.maskIndex) == [30])
        model.set(.tintColor(paint), to: 1)
        #expect(model.identity.face.tints.first?.color == Self.blue.color)
        #expect(model.identity.face.tints.first?.strength == 0.5)
        model.set(.tintMask(paint), to: 2)
        #expect(model.identity.face.tints.map(\.maskIndex) == [31], "one paint at a time")
        model.set(.tintMask(paint), to: 0)
        #expect(model.identity.face.tints.isEmpty)
    }

    /// A face with no tint layers would show its bare grey texture, so the menu
    /// opens with the first preset's tints and keeps the face's own parts.
    @Test func anUnmadeFaceOpensWithThePresetTints() {
        let skin = PlayerTintLayer(maskIndex: 6, color: [220, 180, 160, 255], strength: 1)
        let preset = RacePreset(
            name: "Nord", face: PlayerFace(headParts: [FormID(0xA9)], tints: [skin])
        )
        var identity = Self.identity
        identity.face.headParts = [FormID(0xA1)]
        let fresh = RaceMenuModel(
            identity: identity, races: [], limited: false,
            options: RaceMenuOptions(presets: [preset])
        )
        #expect(fresh.identity.face.tints == [skin])
        #expect(fresh.identity.face.headParts == [FormID(0xA1)])
        identity.face.tints = [PlayerTintLayer(maskIndex: 6, color: [90, 60, 40, 255], strength: 1)]
        let made = RaceMenuModel(
            identity: identity, races: [], limited: false,
            options: RaceMenuOptions(presets: [preset])
        )
        #expect(made.identity.face.tints == identity.face.tints)
    }

    /// Some presets have no skin tone layer. The face takes the mask's `TIND` colour
    /// at its strength, so it is not white, and the body tone follows it.
    @Test func aPresetWithoutSkinToneTakesTheRaceDefault() {
        let grey = RaceMenuColor(formID: FormID(0x21), color: [235, 235, 235, 0], strength: 0.79)
        let skin = RaceMenuTintMask(
            index: 4, type: RaceMenuModel.skinToneType, colors: [Self.red, grey],
            defaultColor: grey
        )
        let lips = PlayerTintLayer(maskIndex: 9, color: [80, 9, 1, 0], strength: 0.5)
        let preset = RacePreset(name: "Khajiit", face: PlayerFace(tints: [lips]))
        let model = RaceMenuModel(
            identity: Self.identity, races: [], limited: false,
            options: RaceMenuOptions(presets: [preset], tintMasks: [skin])
        )
        let layer = PlayerTintLayer(maskIndex: 4, color: [235, 235, 235, 0], strength: 0.79)
        #expect(model.identity.face.tints == [layer, lips])
        #expect(model.position(.tintColor(RaceMenuModel.skinToneType)) == 1)
        #expect(model.bodyToneLine == "Body tone: rgb 212 212 212")
    }
}
