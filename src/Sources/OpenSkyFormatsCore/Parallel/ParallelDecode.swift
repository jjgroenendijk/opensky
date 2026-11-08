// The fan-out a cell build uses to decode assets and records on every core before its
// serial code asks for them (docs/decisions/concurrency.md). Work only turns values into
// values; the caller writes the results into its caches on the build thread.

import Foundation
import Synchronization

nonisolated public enum ParallelDecode {
    /// Fewer items than this run serially: the fan-out costs more than it saves.
    public static let minimumParallelItems = 4
    /// Two cores stay free for the frame loop and the GPU driver, so streaming does not
    /// slow the frames that draw meanwhile.
    public static let workerCount = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)

    /// Runs `work` for each key on `workerCount` shared threads and returns once all are done.
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
        let next = Atomic<Int>(0)
        DispatchQueue.concurrentPerform(iterations: min(keys.count, workerCount)) { _ in
            while true {
                let index = next.add(1, ordering: .relaxed).oldValue
                guard index < keys.count else { return }
                // Shared worker threads do not drain an autorelease pool per item, so the
                // Metal objects a texture fill makes would stay alive until the thread retires.
                autoreleasepool {
                    guard let value = work(keys[index]) else { return }
                    results.withLock { $0[keys[index]] = value }
                }
            }
        }
        return results.withLock { $0 }
    }

    /// `work` over every item, in chunks on the shared threads; the result keeps the
    /// input order, so it does not depend on which thread finished first.
    public static func mapInOrder<Item: Sendable, Value: Sendable>(
        _ items: [Item],
        chunkSize: Int,
        inParallel: Bool = true,
        _ work: @Sendable (Item) -> Value
    ) -> [Value] {
        guard inParallel else { return items.map(work) }
        let starts = Array(stride(from: 0, to: items.count, by: max(chunkSize, 1)))
        let chunks = map(starts.indices) { chunk in
            let start = starts[chunk]
            return items[start ..< min(start + max(chunkSize, 1), items.count)].map(work)
        }
        return starts.indices.flatMap { chunks[$0] ?? [] }
    }
}
