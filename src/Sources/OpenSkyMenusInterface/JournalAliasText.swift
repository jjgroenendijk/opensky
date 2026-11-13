import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// Resolves one quest alias to the display name of whatever fills it, and
/// substitutes those names into journal text.
nonisolated public struct QuestAliasNaming: Sendable {
    /// Opening delimiter of a replacement tag.
    public static let tagOpen: Character = "<"
    public static let tagClose: Character = ">"
    /// Tag body prefix, matched case-insensitively because the Creation Kit
    /// has never treated authored names as case-sensitive.
    public static let aliasKeyword = "alias"

    /// Naming that resolves nothing, so every tag survives as written.
    public static let none: QuestAliasNaming = {
        var naming = QuestAliasNaming { _, _ in nil }
        naming.marksMissingTags = false
        return naming
    }()

    private let name: @Sendable (FormID, UInt32) -> String?
    package let isFemale: @Sendable (FormID, UInt32) -> Bool?
    /// `<Alias=Player>` works in a quest with no `Player` alias.
    public var player: AliasFill?
    public var pronouns = GameSettingTexts<PronounText>.vanilla
    /// The current value of a global, by editor ID, for the `<Global=...>` tags.
    public var global: @Sendable (String) -> Float? = { _ in nil }
    public var replacementTexts = GameSettingTexts<TextReplacementText>.vanilla
    /// A tag whose alias or global has no value shows `sInvalidTagString`. Off, it stays
    /// as written, for a listing with no session behind it.
    public var marksMissingTags = true

    public init(
        name: @escaping @Sendable (FormID, UInt32) -> String?,
        isFemale: @escaping @Sendable (FormID, UInt32) -> Bool? = { _, _ in nil }
    ) {
        self.name = name
        self.isFemale = isFemale
    }

    /// Display name filling one alias of one quest, or nil when nothing does.
    public func name(ofAlias aliasID: UInt32, in quest: FormID) -> String? {
        name(quest, aliasID)
    }
}

/// What fills one alias: the name, and the sex the pronoun tags need.
nonisolated public struct AliasFill: Equatable, Sendable {
    public var name: String
    public var isFemale: Bool?

    public init(name: String, isFemale: Bool?) {
        self.name = name
        self.isFemale = isFemale
    }
}

/// The words of the `<Alias.Pronoun...>` tags.
nonisolated public enum PronounText: String, GameSettingTextKey {
    case male = "sPronounMale", female = "sPronounFemale"
    case objectMale = "sPronounObjMale", objectFemale = "sPronounObjFemale"
    case possessiveMale = "sPronounPosMale", possessiveFemale = "sPronounPosFemale"
    case possessiveObjectMale = "sPronounPosObjMale"
    case possessiveObjectFemale = "sPronounPosObjFemale"
    case reflexiveMale = "sPronounRefMale", reflexiveFemale = "sPronounRefFemale"
    case intensiveMale = "sPronounIntMale", intensiveFemale = "sPronounIntFemale"

    public var fallback: String {
        switch self {
        case .male: "he"
        case .female: "she"
        case .objectMale: "him"
        case .objectFemale, .possessiveObjectFemale: "her"
        case .possessiveMale, .possessiveObjectMale: "his"
        case .possessiveFemale: "hers"
        case .reflexiveMale, .intensiveMale: "himself"
        case .reflexiveFemale, .intensiveFemale: "herself"
        }
    }

    /// The two words of one lower-cased subtag, or nil when it is no pronoun.
    package static func pair(subtag: String) -> (male: Self, female: Self)? {
        switch subtag {
        case "pronoun": (.male, .female)
        case "pronounobj": (.objectMale, .objectFemale)
        case "pronounpos": (.possessiveMale, .possessiveFemale)
        case "pronounposobj": (.possessiveObjectMale, .possessiveObjectFemale)
        case "pronounref": (.reflexiveMale, .reflexiveFemale)
        case "pronounint": (.intensiveMale, .intensiveFemale)
        default: nil
        }
    }
}
