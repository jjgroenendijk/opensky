// The shared off-main asset loader over an immediate worker and a serial one.

@testable import OpenSkyGameData
import Synchronization
import Testing

nonisolated private struct MissingAsset: Error, CustomStringConvertible {
    var description: String {
        "missing"
    }
}

nonisolated private final class LoadCounter: Sendable {
    let loads = Mutex([String]())

    func load(_ key: String) throws -> Int {
        loads.withLock { $0.append(key) }
        guard key != "bad" else { throw MissingAsset() }
        return key.count
    }
}

@MainActor
struct AssetLoaderTests {
    private static func immediate(_ counter: LoadCounter) -> AssetLoader<String, Int> {
        AssetLoader(worker: ImmediateAssetLoadWorker(load: counter.load))
    }

    @Test func aValueArrivesAtTheDrainAfterItsRequest() {
        let counter = LoadCounter()
        let loader = Self.immediate(counter)
        #expect(loader.value(for: "abc") == nil)
        #expect(loader.pendingCount == 1)
        #expect(loader.drain() == ["abc"])
        #expect(loader.value(for: "abc") == 3)
        #expect(loader.pendingCount == 0)
    }

    @Test func aKeyIsPostedOnceWhileItLoads() {
        let counter = LoadCounter()
        let loader = Self.immediate(counter)
        _ = loader.state(of: "abc")
        _ = loader.state(of: "abc")
        loader.prefetch("abc")
        loader.drain()
        _ = loader.state(of: "abc")
        #expect(counter.loads.withLock { $0 } == ["abc"])
    }

    @Test func aFailureIsRememberedAndNotLoadedAgain() {
        let counter = LoadCounter()
        let loader = Self.immediate(counter)
        _ = loader.state(of: "bad")
        loader.drain()
        guard case let .failed(failure) = loader.state(of: "bad") else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.reason == "missing")
        loader.prefetch("bad")
        #expect(loader.failureCount == 1)
        #expect(counter.loads.withLock { $0 } == ["bad"])
    }

    @Test func evictionDropsValuesButKeepsFailures() {
        let loader = Self.immediate(LoadCounter())
        _ = loader.state(of: "abc")
        _ = loader.state(of: "bad")
        loader.drain()
        loader.evict { _ in true }
        #expect(loader.readyCount == 0)
        #expect(loader.failureCount == 1)
    }

    @Test func theSerialWorkerHandsResultsToALaterDrain() async {
        let loader = AssetLoader<String, Int> { $0.count }
        #expect(loader.value(for: "abcd") == nil)
        for _ in 0 ..< 1000 where loader.value(for: "abcd") == nil {
            loader.drain()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(loader.value(for: "abcd") == 4)
    }
}
