// The app's load runner: the result reaches the main actor, and a cancelled
// load never completes.

@testable import OpenSky
import OpenSkyWorld
import Testing

@MainActor
struct WorldLoaderTests {
    @Test
    func deliversTheResultOnTheMainActor() async {
        let loader = WorldLoader()
        let result: Int = await withCheckedContinuation { continuation in
            loader.start(
                work: { progress in try progress.measure(.dialogue) { 7 } },
                onUpdate: { _, _ in },
                completion: { continuation.resume(returning: $0) }
            )
        }
        #expect(result == 7)
        #expect(!loader.isLoading)
    }

    @Test
    func cancelledLoadNeverCompletes() async throws {
        let loader = WorldLoader()
        let (workEnded, signal) = AsyncStream.makeStream(of: Void.self)
        var completions = 0
        loader.start(
            work: { _ in
                defer { signal.yield() }
                try await Task.sleep(for: .seconds(10))
                return 1
            },
            onUpdate: { _, _ in },
            completion: { _ in completions += 1 }
        )
        loader.cancel()
        #expect(!loader.isLoading)
        for await _ in workEnded {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(completions == 0)
    }
}
