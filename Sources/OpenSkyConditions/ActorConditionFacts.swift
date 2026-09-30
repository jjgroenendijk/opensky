// Per-actor facts plus the record store their FormID parameters resolve
// against: the shared shape of the crime, faction, magic and perk seams.
// See docs/engine/condition-functions.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// A load-order store that a condition's FormID parameter resolves against.
nonisolated public protocol ConditionParameterStore: Sendable {
    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID?
    func containsRecord(_ id: ResolvedFormID) -> Bool
}

/// One fact per actor, snapshotted on the main actor so an evaluator off it
/// never reaches into a live runtime. A nil store means the seam cannot answer,
/// which is a different answer from "this actor has no fact".
nonisolated public struct ActorConditionFacts<Store: ConditionParameterStore, Fact: Sendable>:
    Sendable
{
    public let store: Store?
    /// The plugin a condition's FormID parameters are spelled against.
    public let sourcePlugin: String?

    private let facts: [ReferenceKey: Fact]

    public init(
        store: Store? = nil,
        sourcePlugin: String? = nil,
        facts: [ReferenceKey: Fact] = [:]
    ) {
        self.store = store
        self.sourcePlugin = sourcePlugin
        self.facts = facts
    }

    public var isAvailable: Bool {
        store != nil
    }

    /// The parameter as a runtime key, whether or not a record exists for it.
    public func resolvedKey(of formID: FormID) -> ReferenceKey? {
        guard let sourcePlugin, let resolved = store?.resolvedID(formID, fromPlugin: sourcePlugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// The parameter as a runtime key. The record must exist, not just resolve,
    /// so "no such record" stays apart from "the actor does not hold it".
    public func key(of formID: FormID) -> ReferenceKey? {
        guard
            let sourcePlugin,
            let store,
            let resolved = store.resolvedID(formID, fromPlugin: sourcePlugin),
            store.containsRecord(resolved)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }

    /// The fact stored for `actor`, whether or not the store is wired.
    public func fact(of actor: ReferenceKey) -> Fact? {
        facts[actor]
    }
}

nonisolated extension FactionStore: ConditionParameterStore {
    public func containsRecord(_ id: ResolvedFormID) -> Bool {
        faction(id) != nil
    }
}

nonisolated extension PerkStore: ConditionParameterStore {
    public func containsRecord(_ id: ResolvedFormID) -> Bool {
        perk(id) != nil
    }
}

nonisolated extension SpellStore: ConditionParameterStore {
    public func containsRecord(_ id: ResolvedFormID) -> Bool {
        spell(id) != nil
    }
}

nonisolated extension MagicEffectStore: ConditionParameterStore {
    public func containsRecord(_ id: ResolvedFormID) -> Bool {
        effect(id) != nil
    }
}
