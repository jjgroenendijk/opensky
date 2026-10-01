// Alias substitution in journal text. Vanilla writes `<Alias=Prisoner>` or
// `<Alias.ShortName=Jail>` (<https://ck.uesp.net/wiki/Text_Replacement>).
// OpenSky has one name per reference, so every qualifier gives the same name.
// An unresolvable tag stays as written, so a missing fill stays visible.

import Foundation
import OpenSkyFormatsESM

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

    public init(name: @escaping @Sendable (FormID, UInt32) -> String?) {
        self.name = name
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
