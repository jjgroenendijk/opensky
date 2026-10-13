// The race menu's controls in the vanilla order: seven categories, each control with
// its `sRSM` label. Which `NAM9` slider and `TINP` type each control edits is listed in
// docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum RaceMenuRow: Equatable, Hashable, Sendable {
    case race, sex, weight, name
    /// A `NAM9` slider by index.
    case slider(Int)
    /// A `NAMA` group by index: 0 nose, 2 eyes, 3 mouth.
    case part(Int)
    case headPreset
    case headPart(HeadPart.PartType)
    case hairColor
    case complexion
    /// The colour of the tint mask of one `TINP` type.
    case tintColor(UInt16)
    /// Which mask of one `TINP` type, or none: war paint and dirt.
    case tintMask(UInt16)
}

/// The movie's category tabs. Each value is the filter flag its controls carry.
nonisolated public enum RaceMenuCategory: Int, CaseIterable, Sendable {
    case race = 1, body = 2, head = 4, face = 8, eyes = 16, brow = 32, mouth = 64

    public var labelKey: String {
        switch self {
        case .race: "sRSMRace"
        case .body: "sRSMBody"
        case .head: "sRSMHead"
        case .face: "sRSMFace"
        case .eyes: "sRSMEyes"
        case .brow: "sRSMBrow"
        case .mouth: "sRSMMouth"
        }
    }
}

nonisolated public struct RaceMenuControl: Equatable, Sendable {
    public let row: RaceMenuRow
    public let category: RaceMenuCategory
    /// The `sRSM` game setting that names it.
    public let labelKey: String
}

nonisolated extension RaceMenuModel {
    static let paintType: UInt16 = 7
    static let dirtType: UInt16 = 14
    /// Types whose masks the player picks one of, with a colour for the pick.
    static let choiceTintTypes: Set<UInt16> = [paintType, dirtType]

    public static let layout: [RaceMenuControl] = race + body + head + face + eyes + brow
        + mouth

    private static func control(
        _ row: RaceMenuRow, _ category: RaceMenuCategory, _ key: String
    ) -> RaceMenuControl {
        RaceMenuControl(row: row, category: category, labelKey: "sRSM" + key)
    }

    private static let race = [control(.race, .race, "Race")]
    private static let body = [
        control(.sex, .body, "Sex"), control(.tintColor(6), .body, "Tone"),
        control(.weight, .body, "Weight")
    ]
    private static let head = [
        control(.headPreset, .head, "HeadPresets"), control(.headPart(.hair), .head, "Hair"),
        control(.hairColor, .head, "HairColorPresets"),
        control(.headPart(.facialHair), .head, "FacialHairPresets"),
        control(.headPart(.scar), .head, "Scars"), control(.complexion, .head, "Complexion"),
        control(.tintMask(dirtType), .head, "Dirt"),
        control(.tintColor(dirtType), .head, "DirtColor"),
        control(.tintMask(paintType), .head, "Paint"),
        control(.tintColor(paintType), .head, "PaintColor"),
        control(.tintColor(8), .head, "LaughLines"), control(
            .tintColor(13),
            .head,
            "ForeheadColor"
        ),
        control(.tintColor(12), .head, "NeckColor")
    ]
    private static let face = [
        control(.part(0), .face, "NoseTypes"), control(.slider(1), .face, "NoseHeight"),
        control(.slider(0), .face, "NoseLength"), control(.tintColor(10), .face, "NoseColor"),
        control(.slider(3), .face, "JawWidth"), control(.slider(2), .face, "JawHeight"),
        control(.slider(4), .face, "JawForward"), control(.slider(5), .face, "CheekboneHeight"),
        control(.slider(6), .face, "CheekboneWidth"), control(.tintColor(2), .face, "CheekColor"),
        control(.tintColor(9), .face, "CheekColorLower"), control(.slider(14), .face, "ChinWidth"),
        control(.slider(15), .face, "ChinLength"), control(.slider(16), .face, "ChinForward"),
        control(.tintColor(11), .face, "ChinColor")
    ]
    private static let eyes = [
        control(.part(2), .eyes, "EyeTypes"), control(.headPart(.eyes), .eyes, "EyeColor"),
        control(.slider(7), .eyes, "EyeHeight"), control(.slider(8), .eyes, "EyeWidth"),
        control(.slider(17), .eyes, "EyeDepth"), control(.tintColor(3), .eyes, "EyelinerColor"),
        control(.tintColor(4), .eyes, "EyeSocketUpperColor"),
        control(.tintColor(5), .eyes, "EyeSocketLowerColor")
    ]
    private static let brow = [
        control(.headPart(.eyebrows), .brow, "BrowTypes"),
        control(.slider(9), .brow, "BrowHeight"), control(.slider(10), .brow, "BrowWidth"),
        control(.slider(11), .brow, "BrowForward")
    ]
    private static let mouth = [
        control(.part(3), .mouth, "MouthTypes"), control(.slider(12), .mouth, "MouthHeight"),
        control(.slider(13), .mouth, "MouthForward"), control(.tintColor(1), .mouth, "LipColor")
    ]

    public static func control(for row: RaceMenuRow) -> RaceMenuControl? {
        layout.first { $0.row == row }
    }
}
