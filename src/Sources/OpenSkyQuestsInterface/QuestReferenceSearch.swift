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
    /// Every persistent reference of the load order, loaded or not. A match search not
    /// limited to the loaded area reads it after a loaded miss.
    public var persistent: RuntimeReferenceIndex?
    /// Every actor the saved state marks dead, loaded or not.
    public var savedDead: Set<ReferenceKey> = []
    /// The NPC bases, as the plugin spells them, with a dead placed actor.
    public var deadBases: Set<FormID> = []
    /// The saved and plugin enable state of a reference outside the loaded area.
    public var isDisabledOutside: @MainActor @Sendable (ReferenceKey) -> Bool = { _ in false }
    public var isDeleted: @MainActor @Sendable (ReferenceKey) -> Bool = { _ in false }
    public var isDestroyed: @MainActor @Sendable (ReferenceKey) -> Bool = { _ in false }
    /// True for the search `outsideLoadedArea()` returns.
    public private(set) var isOutside = false

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

    /// The same search over the persistent references outside the loaded area, or nil
    /// without a persistent index. Dead and disabled come from the saved state there.
    public func outsideLoadedArea() -> QuestReferenceSearch? {
        guard let persistent else { return nil }
        var outside = self
        outside.references = persistent
        outside.context.references = persistent
        outside.dead = savedDead
        outside.isDisabled = isDisabledOutside
        outside.persistent = nil
        outside.isOutside = true
        return outside
    }

    /// Dead for an alias fill. Outside the loaded area, a reference that a location
    /// stores also counts as dead once any actor of its base has died.
    public func countsAsDead(_ key: ReferenceKey) -> Bool {
        if dead.contains(key) {
            return true
        }
        guard isOutside, !deadBases.isEmpty, let actor = references[key]?.placedActor else {
            return false
        }
        return !actor.details.locationRefTypes.isEmpty && deadBases.contains(actor.base)
    }

    /// The one loaded actor placed from `base` by the base's own plugin, or nil with
    /// none or several. A unique actor placed as a temporary reference is in no
    /// persistent index, so only the loaded cells know it.
    public func loadedActor(ofBase base: ReferenceKey) -> ReferenceKey? {
        guard case let .plugin(plugin, objectID) = base else { return nil }
        let found = references.sortedEntries().filter { entry in
            guard
                let actor = entry.placedActor, case let .plugin(name, _) = entry.key
            else { return false }
            return name == plugin && actor.base.rawValue & Self.objectIDMask == objectID
        }
        return found.count == 1 ? found[0].key : nil
    }

    /// The low 24 bits of a FormID, without the plugin index.
    private static let objectIDMask: UInt32 = 0x00FF_FFFF

    public func deletes(_ key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { isDeleted(key) }
    }

    public func destroys(_ key: ReferenceKey) -> Bool {
        MainActor.assumeIsolated { isDestroyed(key) }
    }

    /// Dead or disabled for a reference that may be loaded or not.
    public func state(of key: ReferenceKey) -> (isDead: Bool, isDisabled: Bool) {
        if references[key] != nil {
            return (countsAsDead(key), disables(key))
        }
        guard let outside = outsideLoadedArea() else { return (false, false) }
        return (outside.countsAsDead(key), outside.disables(key))
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
