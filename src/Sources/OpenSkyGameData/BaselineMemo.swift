// Remembers record-side baselines the per-frame loops would otherwise derive again.
// Plugin records do not change while the game runs, so an answer stays valid for as
// long as the runtime that owns the memo. A class, so a value-type runtime shares it.

/// Values computed once per key and kept, on the main actor.
public final class BaselineMemo<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]

    public init() {}

    public func value(for key: Key, orCompute compute: () -> Value) -> Value {
        if let value = values[key] {
            return value
        }
        let value = compute()
        values[key] = value
        return value
    }
}
