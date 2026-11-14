import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyWorldState
import simd

/// The loaded world one alias fill pass searches. Built once per quest start.
nonisolated public struct QuestReferenceSearch: Sendable {
    /// Every loaded reference.
    public var references: RuntimeReferenceIndex
    /// The player's feet, which "Closest" measures from.
    public var origin: SIMD3<Float>?
    /// The context the match conditions read; the filler sets subject and quest.
    public var context: ConditionContext
    public var dead: Set<ReferenceKey>
    /// Read only for the candidates a match tests, so a search walks no references.
    /// Conditions and searches run on the main actor, as the whole simulation does.
    public var isDisabled: @MainActor @Sendable (ReferenceKey) -> Bool

    public init(
        references: RuntimeReferenceIndex,
        origin: SIMD3<Float>?,
        context: ConditionContext,
        dead: Set<ReferenceKey> = [],
        isDisabled: @escaping @MainActor @Sendable (ReferenceKey) -> Bool = { _ in false }
    ) {
        self.references = references
        self.origin = origin
        self.context = context
        self.dead = dead
        self.isDisabled = isDisabled
    }

    public func disables(_ key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { isDisabled(key) }
    }

    /// The loaded references whose untagged linked ref (`XLKR`) is `parent`, as the
    /// "Linked Ref Child" near type asks.
    public func linkedChildren(of parent: ReferenceKey) -> [ReferenceKey] {
        references.sortedEntries().filter { entry in
            let link = entry.placedReference?.linkedReference()
                ?? entry.placedActor?.details.linkedReferences.first { $0.keyword == nil }?.ref
            return link.flatMap { references.entry(for: $0)?.key } == parent
        }.map(\.key)
    }

    package func position(of key: ReferenceKey) -> SIMD3<Float>? {
        guard let entry = references[key] else { return nil }
        return entry.placedReference?.placement.position ?? entry.placedActor?.placement.position
    }
}
