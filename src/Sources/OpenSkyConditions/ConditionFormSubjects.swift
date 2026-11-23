// Base forms a condition runs on in place of a placed reference: the weapon, item,
// spell, or enchantment tab of a perk effect. `HasKeyword`, `GetIsID`, and `IsInList`
// read them. See docs/engine/perks.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One base form standing in as a run-on subject.
nonisolated public struct ConditionFormSubject: Equatable, Sendable {
    public let id: ResolvedFormID
    /// The keywords of a magic item's effects. A spell or an enchantment has no `KWDA`,
    /// so `HasKeyword` reads these. Nil reads the form's own `KWDA`.
    public let effectKeywords: Set<ReferenceKey>?

    public init(id: ResolvedFormID, effectKeywords: Set<ReferenceKey>? = nil) {
        self.id = id
        self.effectKeywords = effectKeywords
    }

    /// The key a run-on names this form by.
    public var key: ReferenceKey {
        ReferenceKey(resolved: id)
    }
}

/// The base forms bound for one evaluation, by the key a run-on names.
nonisolated public struct FormSubjectResolution: ConditionResolution, Sendable {
    public static let empty = FormSubjectResolution(forms: [])

    public let forms: [ReferenceKey: ConditionFormSubject]

    public init(forms: [ConditionFormSubject]) {
        self.forms = Dictionary(forms.map { ($0.key, $0) }) { first, _ in first }
    }
}

nonisolated extension ConditionCall {
    /// The base form the run-on names, or nil when it names a placed reference.
    public func formSubject() -> ConditionFormSubject? {
        guard case let .success(key) = referenceKey() else { return nil }
        return context[resolution: FormSubjectResolution.self].forms[key]
    }

    /// `parameter` as a form in the load-order stores, or nil when it does not resolve.
    func resolvedParameter(_ parameter: Condition.Parameter) -> ResolvedFormID? {
        guard let sourcePlugin = context.data.sourcePlugin else { return nil }
        return context.data.keywords?.resolvedID(parameter.asFormID, fromPlugin: sourcePlugin)
    }
}

nonisolated extension ConditionFunctions {
    /// `HasKeyword` on a base form: its effects' keywords, or its own `KWDA`.
    static func formHasKeyword(
        _ form: ConditionFormSubject,
        keyword: ResolvedFormID,
        store: KeywordStore
    ) -> Result<Float, ConditionFailure> {
        if let effectKeywords = form.effectKeywords {
            return .success(isTrue(effectKeywords.contains(ReferenceKey(resolved: keyword))))
        }
        guard let answer = store.hasKeyword(keyword, on: form.id) else {
            return .failure(.unavailableData(.keyword))
        }
        return .success(isTrue(answer))
    }

    /// `HasKeyword` on a placed reference: an alias that holds it gives keywords
    /// (<https://ck.uesp.net/wiki/Quest_Alias_Tab>), else its base's `KWDA`.
    static func referenceHasKeyword(
        _ entry: RuntimeReferenceEntry,
        keyword: ResolvedFormID,
        store: KeywordStore,
        aliases: (any ConditionAliasResolving)?
    ) -> Result<Float, ConditionFailure> {
        if aliases?.aliasGivesKeyword(keyword, to: entry.key) == true {
            return .success(1)
        }
        guard
            let base = store.resolvedID(
                baseForm(of: entry), fromPlugin: ConditionFunctionsData.basePlugin(of: entry.key)
            ),
            let answer = store.hasKeyword(keyword, on: base)
        else { return .failure(.unavailableData(.keyword)) }
        return .success(isTrue(answer))
    }

    /// `GetIsID` on a base form. Plugin names compare without case.
    static func formIsID(
        _ form: ConditionFormSubject,
        _ parameter: Condition.Parameter,
        call: ConditionCall
    ) -> Result<Float, ConditionFailure> {
        guard let wanted = call.resolvedParameter(parameter) else {
            return .failure(.unavailableData(.keyword))
        }
        return .success(isTrue(ReferenceKey(resolved: wanted) == form.key))
    }
}
