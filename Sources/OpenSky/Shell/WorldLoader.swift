// Runs one world load off the main actor and reports its stages back to the
// launcher. The main actor never waits: progress and the result arrive as tasks.

import Foundation
import OpenSkyWorld

final class WorldLoader {
    /// The stages of the newest load, kept after it ends for the timing inspector.
    private(set) var timeline = WorldLoadTimeline()
    private(set) var elapsed = Duration.zero
    var isLoading: Bool {
        loadTask != nil
    }

    private var loadTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var generation = 0

    /// `work` runs off the main actor. `completion` runs on the main actor with
    /// its result, or not at all once the load is cancelled.
    func start<Result>(
        work: @escaping @Sendable (WorldLoadProgress) async throws -> sending Result,
        onUpdate: @escaping (WorldLoadTimeline, Duration) -> Void,
        completion: @escaping (Result) -> Void
    ) {
        cancel()
        generation += 1
        let current = generation
        let start = ContinuousClock.now
        timeline = WorldLoadTimeline()
        elapsed = .zero
        let (events, continuation) = AsyncStream.makeStream(of: WorldLoadEvent.self)
        let progress = WorldLoadProgress { continuation.yield($0) }
        watchTask = Task { [weak self] in
            await self?.watch(events, start: start, generation: current, onUpdate: onUpdate)
        }
        loadTask = Task { [weak self] in
            let result = try? await work(progress)
            continuation.finish()
            guard let self, generation == current, let result else { return }
            elapsed = ContinuousClock.now - start
            loadTask = nil
            completion(result)
        }
    }

    func cancel() {
        loadTask?.cancel()
        watchTask?.cancel()
        loadTask = nil
        watchTask = nil
    }

    /// Applies each stage event, and redraws ten times a second so the elapsed
    /// time moves while a long stage runs.
    private func watch(
        _ events: AsyncStream<WorldLoadEvent>,
        start: ContinuousClock.Instant,
        generation current: Int,
        onUpdate: @escaping (WorldLoadTimeline, Duration) -> Void
    ) async {
        let ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, generation == current, isLoading else { return }
                onUpdate(timeline, ContinuousClock.now - start)
            }
        }
        defer { ticker.cancel() }
        for await event in events {
            guard generation == current else { return }
            timeline.apply(event)
            onUpdate(timeline, ContinuousClock.now - start)
        }
    }
}
