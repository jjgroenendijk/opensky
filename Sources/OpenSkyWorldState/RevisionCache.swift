// One value kept until the inputs it was built from change.
// See docs/engine/runtime-state.md#caching-derived-views.

/// `Key` holds the revisions and the cheap inputs the value reads, so an unchanged
/// key means the value a fresh build would give.
@MainActor
public final class RevisionCache<Key: Equatable, Value> {
    private var entry: (key: Key, value: Value)?

    public init() {}

    public func value(for key: Key, build: () -> Value) -> Value {
        if let entry, entry.key == key {
            return entry.value
        }
        let value = build()
        entry = (key, value)
        return value
    }
}
