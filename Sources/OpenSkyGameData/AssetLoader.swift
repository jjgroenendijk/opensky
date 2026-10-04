// Loads assets off the main actor during play: a coordinator requests a key, a
// worker reads and decodes it, and the frame drains finished results at one point.
// See docs/decisions/concurrency.md.

import Foundation
import Synchronization

nonisolated public enum AssetLoadPriority: Sendable {
    /// Something waits for the asset now.
    case needed
    /// Warm-up for a later use; runs after every needed load.
    case prefetch
}

nonisolated public struct AssetLoadFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public init(_ error: any Error) {
        reason = String(describing: error)
    }

    public var description: String {
        reason
    }
}

nonisolated public struct AssetLoadCompletion<Key: Sendable, Value: Sendable>: Sendable {
    public let key: Key
    public let result: Result<Value, AssetLoadFailure>

    public init(key: Key, result: Result<Value, AssetLoadFailure>) {
        self.key = key
        self.result = result
    }
}

/// Where loads run. The worker never calls into main-actor code.
nonisolated public protocol AssetLoadWorking<Key, Value>: Sendable {
    associatedtype Key: Hashable & Sendable
    associatedtype Value: Sendable

    func submit(_ key: Key, priority: AssetLoadPriority)
    /// Finished loads since the last call. Never waits.
    func takeFinished() -> [AssetLoadCompletion<Key, Value>]
}

/// The one serial queue every play-time load shares, so loads never compete
/// with each other for cores the cell build worker needs.
nonisolated public enum AssetLoadQueue {
    public static let shared = DispatchQueue(
        label: "nl.jjgroenendijk.opensky.assetload", qos: .userInitiated
    )
}

/// Runs each load on a serial queue, needed loads before prefetches.
nonisolated public final class SerialAssetLoadWorker<Key: Hashable & Sendable, Value: Sendable>:
    AssetLoadWorking, Sendable
{
    nonisolated private struct Pending {
        var needed: [Key] = []
        var prefetch: [Key] = []

        mutating func next() -> Key? {
            if !needed.isEmpty {
                return needed.removeFirst()
            }
            return prefetch.isEmpty ? nil : prefetch.removeFirst()
        }
    }

    private let load: @Sendable (Key) throws -> Value
    private let queue: DispatchQueue
    private let pending = Mutex(Pending())
    private let finished = Mutex([AssetLoadCompletion<Key, Value>]())

    public init(
        queue: DispatchQueue = AssetLoadQueue.shared,
        load: @escaping @Sendable (Key) throws -> Value
    ) {
        self.queue = queue
        self.load = load
    }

    public func submit(_ key: Key, priority: AssetLoadPriority) {
        pending.withLock {
            switch priority {
            case .needed: $0.needed.append(key)
            case .prefetch: $0.prefetch.append(key)
            }
        }
        // One block per submit; each block runs the most urgent pending key.
        queue.async { [self] in
            guard let key = pending.withLock({ $0.next() }) else { return }
            let result = Result { try load(key) }.mapError(AssetLoadFailure.init)
            finished.withLock { $0.append(AssetLoadCompletion(key: key, result: result)) }
        }
    }

    public func takeFinished() -> [AssetLoadCompletion<Key, Value>] {
        finished.withLock { finished in
            defer { finished.removeAll(keepingCapacity: true) }
            return finished
        }
    }
}

/// Runs each load inside `submit`, so a test sees the result at the next drain.
nonisolated public final class ImmediateAssetLoadWorker<Key: Hashable & Sendable, Value: Sendable>:
    AssetLoadWorking, Sendable
{
    private let load: @Sendable (Key) throws -> Value
    private let finished = Mutex([AssetLoadCompletion<Key, Value>]())

    public init(load: @escaping @Sendable (Key) throws -> Value) {
        self.load = load
    }

    public func submit(_ key: Key, priority _: AssetLoadPriority) {
        let result = Result { try load(key) }.mapError(AssetLoadFailure.init)
        finished.withLock { $0.append(AssetLoadCompletion(key: key, result: result)) }
    }

    public func takeFinished() -> [AssetLoadCompletion<Key, Value>] {
        finished.withLock { finished in
            defer { finished.removeAll(keepingCapacity: true) }
            return finished
        }
    }
}

nonisolated public enum AssetLoadState<Value: Sendable>: Sendable {
    case loading
    case ready(Value)
    case failed(AssetLoadFailure)

    public var value: Value? {
        guard case let .ready(value) = self else { return nil }
        return value
    }
}

/// The main-actor side: keeps finished values and failures, and posts each key once.
/// Frame code calls `drain()` at one fixed point, so results enter in a fixed order.
public final class AssetLoader<Key: Hashable & Sendable, Value: Sendable> {
    private let worker: any AssetLoadWorking<Key, Value>
    private var ready: [Key: Value] = [:]
    private var failures: [Key: AssetLoadFailure] = [:]
    private var inFlight: Set<Key> = []

    public init(worker: any AssetLoadWorking<Key, Value>) {
        self.worker = worker
    }

    /// A loader whose work runs on the shared play-time queue.
    public convenience init(load: @escaping @Sendable (Key) throws -> Value) {
        self.init(worker: SerialAssetLoadWorker(load: load))
    }

    /// The asset, its failure, or `.loading` after posting a needed request.
    public func state(of key: Key) -> AssetLoadState<Value> {
        if let value = ready[key] {
            return .ready(value)
        }
        if let failure = failures[key] {
            return .failed(failure)
        }
        request(key, priority: .needed)
        return .loading
    }

    /// The asset when it is ready; otherwise requests it and returns nil.
    public func value(for key: Key) -> Value? {
        state(of: key).value
    }

    /// Warms `key` for a later use. A known key is not posted again.
    public func prefetch(_ key: Key) {
        guard ready[key] == nil, failures[key] == nil else { return }
        request(key, priority: .prefetch)
    }

    /// Moves finished loads in. Returns the keys that finished, in completion order.
    @discardableResult
    public func drain() -> [Key] {
        let finished = worker.takeFinished()
        for completion in finished {
            inFlight.remove(completion.key)
            switch completion.result {
            case let .success(value): ready[completion.key] = value
            case let .failure(failure): failures[completion.key] = failure
            }
        }
        return finished.map(\.key)
    }

    /// Forgets values, for example when a cell unloads. Failures stay remembered.
    public func evict(where shouldEvict: (Key) -> Bool) {
        ready = ready.filter { !shouldEvict($0.key) }
    }

    public var pendingCount: Int {
        inFlight.count
    }

    public var readyCount: Int {
        ready.count
    }

    public var failureCount: Int {
        failures.count
    }

    private func request(_ key: Key, priority: AssetLoadPriority) {
        guard inFlight.insert(key).inserted else { return }
        worker.submit(key, priority: priority)
    }
}
