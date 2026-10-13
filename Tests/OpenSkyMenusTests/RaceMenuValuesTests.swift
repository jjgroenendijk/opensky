// The race menu's choice rows: head parts with a "none" choice, hair colour,
// complexion, and war paint with its own colour row.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
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
}
