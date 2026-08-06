// Alias substitution in journal text (issue #184, on top of the alias fills of
// issue #183).
//
// Quest journal paragraphs and objective lines are authored with placeholders
// that name one of the quest's own aliases, and the engine replaces each with
// the display name of whatever filled it. The syntax is measured rather than
// remembered: `openskycli swf quest-journal --text` prints the resolved CNAM
// and NNAM strings of a quest straight out of the plugin's `.dlstrings` table,
// and vanilla `Skyrim.esm` writes them as angle-bracketed tags whose body is
// `Alias` followed by an optional dotted qualifier, then `=`, then the authored
// alias name: `<Alias=Prisoner>`, `<Alias.ShortName=Jail>`.
//
// The Creation Kit documents the same family under "text replacement":
// "<Alias=AliasName> - the name of the object filling the alias"
// (<https://ck.uesp.net/wiki/Text_Replacement>). The qualifier chooses which
// name of that object is wanted; OpenSky has one name per reference, so every
// qualifier resolves to the same string and the qualifier is parsed only so a
// tag carrying one is still recognized as a tag.
//
// Policy for a token that cannot be resolved — no such alias, an empty alias,
// or a reference with no name — is to leave the tag exactly as written. A
// visible `<Alias=Prisoner>` in the journal says "this fill is missing", which
// is a truthful readout; silently deleting it would leave a sentence with a
// hole in it and nothing to point at.

import Foundation

/// Resolves one quest alias to the display name of whatever fills it, and
/// substitutes those names into journal text.
nonisolated struct QuestAliasNaming: Sendable {
    /// Opening delimiter of a replacement tag.
    static let tagOpen: Character = "<"
    static let tagClose: Character = ">"
    /// Tag body prefix, matched case-insensitively because the Creation Kit
    /// has never treated authored names as case-sensitive.
    static let aliasKeyword = "alias"

    /// Naming that resolves nothing, so every tag survives as written.
    static let none = QuestAliasNaming { _, _ in nil }

    private let name: @Sendable (FormID, UInt32) -> String?

    init(name: @escaping @Sendable (FormID, UInt32) -> String?) {
        self.name = name
    }

    /// Display name filling one alias of one quest, or nil when nothing does.
    func name(ofAlias aliasID: UInt32, in quest: FormID) -> String? {
        name(quest, aliasID)
    }

    /// `text` with every resolvable alias tag replaced.
    ///
    /// Scans rather than uses a regular expression so an unterminated `<` costs
    /// nothing: it is copied through with the rest of the sentence.
    func substituting(_ text: String, in quest: Quest) -> String {
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

    /// The name a tag body stands for, or nil when the body is not an alias
    /// tag or names an alias this session cannot resolve.
    private func replacement(for body: Substring, in quest: Quest) -> String? {
        guard let equals = body.firstIndex(of: "=") else { return nil }
        let keyword = body[..<equals]
        // `Alias` or `Alias.<qualifier>`; anything else is a different
        // replacement family (a global, an actor value) and is left alone.
        let head = keyword.split(separator: ".", maxSplits: 1).first ?? ""
        guard head.lowercased() == Self.aliasKeyword else { return nil }
        let aliasName = body[body.index(after: equals)...]
        guard !aliasName.isEmpty else { return nil }
        let wanted = aliasName.lowercased()
        guard
            let alias = quest.aliases.first(where: { $0.name?.lowercased() == wanted })
        else {
            return nil
        }
        return name(ofAlias: alias.id, in: quest.formID)
    }
}
