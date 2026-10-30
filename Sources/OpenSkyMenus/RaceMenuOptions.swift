// What one race and sex offers in the race menu, read from the records, and the
// menu's words from the `sRSM` game settings. See docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One colour choice: a `CLFM` colour with the strength it paints at.
nonisolated public struct RaceMenuColor: Equatable, Sendable {
    public let formID: FormID?
    public let color: SIMD4<UInt8>
    /// 0 to 1.
    public let strength: Float

    public init(formID: FormID?, color: SIMD4<UInt8>, strength: Float = 1) {
        self.formID = formID
        self.color = color
        self.strength = strength
    }
}

/// One race tint mask (`TINI`) and its colour presets (`TINC` with `TINV`).
nonisolated public struct RaceMenuTintMask: Equatable, Sendable {
    public let index: UInt16
    /// `TINP`, such as 6 for skin tone or 7 for war paint.
    public let type: UInt16
    public let colors: [RaceMenuColor]
    /// `TIND`, the colour a face without this mask's layer takes.
    public let defaultColor: RaceMenuColor?

    public init(
        index: UInt16, type: UInt16, colors: [RaceMenuColor], defaultColor: RaceMenuColor? = nil
    ) {
        self.index = index
        self.type = type
        self.colors = colors
        self.defaultColor = defaultColor
    }
}

nonisolated public struct RaceMenuOptions: Equatable, Sendable {
    public var presets: [RacePreset]
    /// Playable head parts the race and sex may wear, by `HDPT` type.
    public var headParts: [HeadPart.PartType: [FormID]]
    /// `AHCM` or `AHCF`.
    public var hairColors: [RaceMenuColor]
    public var tintMasks: [RaceMenuTintMask]
    /// `FTSM` or `FTSF`, face texture sets.
    public var complexions: [FormID]
    /// The highest type the race and sex's chargen TRI holds, by `NAMA` index.
    public var partTypes: [Int: Int] = [:]

    public init(
        presets: [RacePreset] = [], headParts: [HeadPart.PartType: [FormID]] = [:],
        hairColors: [RaceMenuColor] = [], tintMasks: [RaceMenuTintMask] = [],
        complexions: [FormID] = []
    ) {
        self.presets = presets
        self.headParts = headParts
        self.hairColors = hairColors
        self.tintMasks = tintMasks
        self.complexions = complexions
    }

    public static let empty = Self()

    public func masks(ofType type: UInt16) -> [RaceMenuTintMask] {
        tintMasks.filter { $0.type == type && !$0.colors.isEmpty }
    }

    /// Builds the options from the race's head data and the chargen records.
    public static func build(
        head: RaceHeadData,
        parts: (HeadPart.PartType) -> [FormID], color: (FormID) -> SIMD4<UInt8>?,
        presets: [RacePreset]
    ) -> Self {
        let types: [HeadPart.PartType] = [.hair, .facialHair, .scar, .eyes, .eyebrows]
        var headParts: [HeadPart.PartType: [FormID]] = [:]
        for type in types {
            headParts[type] = parts(type)
        }
        let masks = head.tintMasks.compactMap { mask -> RaceMenuTintMask? in
            guard let index = mask.index, let type = mask.maskType else { return nil }
            let colors = mask.presets.compactMap { preset -> RaceMenuColor? in
                guard let id = preset.color, let rgba = color(id) else { return nil }
                return RaceMenuColor(formID: id, color: rgba, strength: preset.strength)
            }
            let defaultColor = mask.defaultPreset.flatMap { preset in
                colors.first { $0.formID == preset.color }
            }
            return RaceMenuTintMask(
                index: index, type: type, colors: colors, defaultColor: defaultColor
            )
        }
        return Self(
            presets: presets, headParts: headParts,
            hairColors: head.hairColors.compactMap { id in
                color(id).map { RaceMenuColor(formID: id, color: $0) }
            },
            tintMasks: masks, complexions: head.faceDetailTextures
        )
    }
}

/// The menu's words: the `sRSM` game settings by editor ID, with English fallbacks.
nonisolated public struct RaceMenuLabels: Equatable, Sendable {
    public static let english: [String: String] = [
        "sRSMRace": "Race", "sRSMBody": "Body", "sRSMHead": "Head", "sRSMFace": "Face",
        "sRSMEyes": "Eyes", "sRSMBrow": "Brow", "sRSMMouth": "Mouth", "sRSMSex": "Sex",
        "sRSMName": "Name", "sRSMWeight": "Weight", "sRSMTone": "Skin Tone",
        "sRSMHeadPresets": "Presets", "sRSMHair": "Hair", "sRSMHairColorPresets": "Hair Color",
        "sRSMFacialHairPresets": "Beard", "sRSMScars": "Scars", "sRSMComplexion": "Complexion",
        "sRSMDirt": "Dirt", "sRSMDirtColor": "Dirt Color", "sRSMPaint": "War Paint",
        "sRSMPaintColor": "War Paint Color", "sRSMLaughLines": "Laugh Lines",
        "sRSMForeheadColor": "Forehead Color", "sRSMNeckColor": "Neck Color",
        "sRSMNoseTypes": "Nose Type", "sRSMNoseHeight": "Nose Height",
        "sRSMNoseLength": "Nose Length", "sRSMNoseColor": "Nose Color",
        "sRSMJawWidth": "Jaw Width", "sRSMJawHeight": "Jaw Height",
        "sRSMJawForward": "Jaw Forward", "sRSMCheekboneHeight": "Cheekbone Height",
        "sRSMCheekboneWidth": "Cheekbone Width", "sRSMCheekColor": "Cheek Color",
        "sRSMCheekColorLower": "Lower Cheek Color", "sRSMChinWidth": "Chin Width",
        "sRSMChinLength": "Chin Length", "sRSMChinForward": "Chin Forward",
        "sRSMChinColor": "Chin Color", "sRSMEyeTypes": "Eye Shape", "sRSMEyeColor": "Eye Color",
        "sRSMEyeHeight": "Eye Height", "sRSMEyeWidth": "Eye Width", "sRSMEyeDepth": "Eye Depth",
        "sRSMEyelinerColor": "Eyeliner Color", "sRSMEyeSocketUpperColor": "Eye Socket Upper",
        "sRSMEyeSocketLowerColor": "Eye Socket Lower", "sRSMBrowTypes": "Brow Type",
        "sRSMBrowHeight": "Brow Height", "sRSMBrowWidth": "Brow Width",
        "sRSMBrowForward": "Brow Forward", "sRSMMouthTypes": "Mouth Type",
        "sRSMMouthHeight": "Mouth Height", "sRSMMouthForward": "Mouth Forward",
        "sRSMLipColor": "Lip Color"
    ]

    /// The install's text by editor ID; a missing one falls back to English.
    public var texts: [String: String]
    public var genders: GameSettingTexts<GenderText>

    public init(
        texts: [String: String] = [:], genders: GameSettingTexts<GenderText> = .vanilla
    ) {
        self.texts = texts
        self.genders = genders
    }

    public func text(_ key: String) -> String {
        texts[key] ?? Self.english[key] ?? key
    }
}

/// The Sex row's value.
nonisolated public enum GenderText: String, GameSettingTextKey {
    case male = "sGenderMale"
    case female = "sGenderFemale"

    public var fallback: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        }
    }
}
