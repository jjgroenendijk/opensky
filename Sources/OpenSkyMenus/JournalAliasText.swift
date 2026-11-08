// Alias substitution in journal text. Vanilla writes `<Alias=Prisoner>` or
// `<Alias.ShortName=Jail>` (<https://ck.uesp.net/wiki/Text_Replacement>).
// The pronoun subtags and the "Cap" suffix follow that page; any other qualifier gives
// the name. An unresolvable tag stays as written, so a missing fill stays visible.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMenusInterface

nonisolated extension QuestAliasNaming {
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

nonisolated extension QuestAliasNaming {
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
}
