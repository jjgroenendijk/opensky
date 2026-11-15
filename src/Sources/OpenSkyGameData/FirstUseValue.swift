// Record data that most sessions never read, decoded on its first read instead of during
// the world load. See docs/decisions/concurrency.md#records-decoded-on-first-use.

import Synchronization

/// Built on the thread of its first read and kept. Two first reads at once build it once:
/// the second waits for the first.
nonisolated public final class FirstUseValue<Value: Sendable>: Sendable {
    private let build: @Sendable () -> Value
    private let slot = Mutex<Value?>(nil)

    public init(_ build: @escaping @Sendable () -> Value) {
        self.build = build
    }

    public var value: Value {
        slot.withLock { slot in
            if let built = slot {
                return built
            }
            let built = build()
            slot = built
            return built
        }
    }

    /// True once a read built the value.
    var isBuilt: Bool {
        slot.withLock { $0 != nil }
    }
}
