// Values derived from the deltas, kept until the next delta write, and the bulk
// writes built on the store's public API. See docs/engine/runtime-state.md.

import OpenSkyFormatsESM

extension WorldStateStore {
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
    private var revision: UInt64 = 0
    private var values: [Key: (revision: UInt64, value: Any)] = [:]

    func invalidate() {
        revision &+= 1
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
