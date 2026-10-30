// Alias substitution in journal text. Vanilla writes `<Alias=Prisoner>` or
// `<Alias.ShortName=Jail>` (<https://ck.uesp.net/wiki/Text_Replacement>).
// The pronoun subtags and the "Cap" suffix follow that page; any other qualifier gives
// the name. An unresolvable tag stays as written, so a missing fill stays visible.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

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
    public static let none = QuestAliasNaming { _, _ in nil }

    private let name: @Sendable (FormID, UInt32) -> String?
    private let isFemale: @Sendable (FormID, UInt32) -> Bool?
    /// `<Alias=Player>` works in a quest with no `Player` alias.
    public var player: AliasFill?
    public var pronouns = GameSettingTexts<PronounText>.vanilla

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

    /// `text` with every resolvable alias tag replaced.
    ///
    /// Scans rather than uses a regular expression so an unterminated `<` costs
    /// nothing: it is copied through with the rest of the sentence.
    public func substituting(_ text: String, in quest: Quest) -> String {
        guard text.contains(Self.tagOpen) else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var rest = Substring(text)
        while let open = rest.firstIndex(of: Self.tagOpen) {
            result += rest[..<open]
            rest = rest[rest.index(after: open)...]
            guard let close = rest.firstIndex(of: Self.tagClose) else {
                // Unterminated tag: put the delimiter back and stop scanning.
                result.append(Self.tagOpen)
                break
            }
            let body = rest[..<close]
            rest = rest[rest.index(after: close)...]
            if let replacement = replacement(for: body, in: quest) {
                result += replacement
            } else {
                result.append(Self.tagOpen)
                result += body
                result.append(Self.tagClose)
            }
        }
        result += rest
        return result
    }

    /// The text a tag body stands for, or nil when the body is not an alias
    /// tag or names an alias this session cannot resolve.
    private func replacement(for body: Substring, in quest: Quest) -> String? {
        guard let equals = body.firstIndex(of: "=") else { return nil }
        let keyword = body[..<equals]
        // `Alias` or `Alias.<qualifier>`; anything else is a different
        // replacement family (a global, an actor value) and is left alone.
        let parts = keyword.split(separator: ".", maxSplits: 1)
        guard (parts.first ?? "").lowercased() == Self.aliasKeyword else { return nil }
        let aliasName = body[body.index(after: equals)...]
        guard !aliasName.isEmpty, let fill = fill(named: aliasName.lowercased(), in: quest)
        else { return nil }
        var subtag = parts.count > 1 ? parts[1].lowercased() : ""
        let capitalised = subtag.hasSuffix("cap")
        if capitalised {
            subtag.removeLast(3)
        }
        let text: String
        if let pronoun = PronounText.pair(subtag: subtag) {
            guard let female = fill.isFemale else { return nil }
            text = pronouns[female ? pronoun.female : pronoun.male]
        } else {
            text = fill.name
        }
        return capitalised ? text.prefix(1).uppercased() + text.dropFirst() : text
    }

    private func fill(named wanted: String, in quest: Quest) -> AliasFill? {
        if let alias = quest.aliases.first(where: { $0.name?.lowercased() == wanted }) {
            return name(ofAlias: alias.id, in: quest.formID).map {
                AliasFill(name: $0, isFemale: isFemale(quest.formID, alias.id))
            }
        }
        return wanted == "player" ? player : nil
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
    static func pair(subtag: String) -> (male: Self, female: Self)? {
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
