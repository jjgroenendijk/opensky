// The fan-out a cell build uses to decode assets on every core before its serial loads
// ask for them (docs/decisions/concurrency.md). Work only turns values into values; the
// caller writes the results into its caches on the build thread.

import Foundation
import Synchronization

nonisolated public enum ParallelDecode {
    /// Fewer items than this run serially: the fan-out costs more than it saves.
    public static let minimumParallelItems = 4

    /// Runs `work` for each key on the system's shared threads and returns once all are done.
    /// A nil result leaves the key out.
    public static func map<Key: Hashable & Sendable, Value: Sendable>(
        _ keys: some Collection<Key>,
        _ work: @Sendable (Key) -> Value?
    ) -> [Key: Value] {
        let keys = Array(keys)
        guard keys.count >= minimumParallelItems else {
            var results: [Key: Value] = [:]
            for key in keys {
                results[key] = work(key)
            }
            return results
        }
        let results = Mutex<[Key: Value]>([:])
        DispatchQueue.concurrentPerform(iterations: keys.count) { index in
            guard let value = work(keys[index]) else { return }
            results.withLock { $0[keys[index]] = value }
        }
        return results.withLock { $0 }
    }
}
