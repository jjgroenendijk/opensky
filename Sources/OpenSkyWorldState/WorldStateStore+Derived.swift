// Values derived from the deltas, kept until the next delta write, and the bulk
// writes built on the store's public API. See docs/engine/runtime-state.md.

import OpenSkyFormatsESM

extension WorldStateStore {
    /// Rises on every delta write and every restore, so a reader can key its own cache.
    public var deltaRevision: UInt64 {
        derivedCache.revision
    }

    /// Rises on every write of one of `kinds` and on every restore. A cache that reads
    /// only these kinds keys on it, so writes of other kinds keep it.
    public func revision(of kinds: [WorldStateComponentKind]) -> UInt64 {
        kinds.reduce(derivedCache.restoreRevision) { $0 &+ derivedCache.revision(of: $1) }
    }

    /// A value built from the deltas and `source`, kept until the next delta write.
    /// Readers that scan many keys each frame use it, such as the quest resolutions.
    public func derived<Value>(
        _ type: Value.Type, from source: AnyObject, build: () -> Value
    ) -> Value {
        derivedCache.value(type, from: source, build: build)
    }

    /// Drops every delta in the store. Journal sequence numbering continues,
    /// because these resets did happen.
    public func resetAll() {
        for key in sortedDirtyKeys() {
            reset(key)
        }
    }

    /// Writes a raw number to a global of declared type `type`.
    @discardableResult
    public func setGlobal(_ raw: Float, type: Global.ValueType, for key: ReferenceKey) -> Bool {
        setGlobal(GlobalValue(type: type, rawValue: raw), for: key)
    }

    /// Drops every global override, in `ReferenceKey` total order so the
    /// journal stays deterministic.
    public func resetAllGlobals() {
        for key in sortedOverriddenGlobalKeys() {
            resetGlobal(for: key)
        }
    }
}

/// A restore does not move the journal sequence, so the cache keeps its own revision.
@MainActor
final class WorldStateDerivedCache {
    private(set) var revision: UInt64 = 0
    private(set) var restoreRevision: UInt64 = 0
    private var kindRevisions: [WorldStateComponentKind: UInt64] = [:]
    private var values: [Key: (revision: UInt64, value: Any)] = [:]

    /// `kind` is the slot written, or nil for a restore, which replaces every slot.
    func invalidate(_ kind: WorldStateComponentKind?) {
        revision &+= 1
        if let kind {
            kindRevisions[kind, default: 0] &+= 1
        } else {
            restoreRevision &+= 1
        }
    }

    func revision(of kind: WorldStateComponentKind) -> UInt64 {
        kindRevisions[kind] ?? 0
    }

    func value<Value>(
        _ type: Value.Type, from source: AnyObject, build: () -> Value
    ) -> Value {
        let key = Key(type: ObjectIdentifier(type), source: ObjectIdentifier(source))
        if
            let cached = values[key], cached.revision == revision,
            let value = cached.value as? Value
        {
            return value
        }
        let value = build()
        values[key] = (revision, value)
        return value
    }

    private struct Key: Hashable {
        let type: ObjectIdentifier
        let source: ObjectIdentifier
    }
}
