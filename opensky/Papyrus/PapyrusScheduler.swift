// Deterministic fixed-step scheduling for latent native continuations.

import Foundation

nonisolated final class PapyrusScheduler {
    private struct Entry {
        let order: UInt64
        let wake: Wake
        let call: SuspendedCall
    }

    private enum Wake {
        case realSeconds(Double)
        case gameHours(Double)
    }

    let runtime: PapyrusRuntime
    let fixedStepSeconds: Double
    let maximumGameHoursPerStep: Double

    private(set) var realSeconds = 0.0
    private(set) var elapsedGameHours = 0.0
    private(set) var pendingCount = 0

    private var lastGameSeconds: Double?
    private var nextOrder: UInt64 = 0
    private var entries: [Entry] = []
    private var terminal: [PapyrusRunOutcome] = []

    init(
        runtime: PapyrusRuntime,
        fixedStepSeconds: Double,
        maximumGameHoursPerStep: Double = 24
    ) {
        self.runtime = runtime
        self.fixedStepSeconds = max(0, fixedStepSeconds)
        self.maximumGameHoursPerStep = max(0, maximumGameHoursPerStep)
    }

    func schedule(_ outcome: PapyrusRunOutcome) {
        route(outcome)
    }

    func tick(gameClock: GameClock? = nil) -> [PapyrusRunOutcome] {
        realSeconds += fixedStepSeconds
        consumeGameTime(gameClock)
        wakeDueCalls()
        let result = terminal
        terminal.removeAll(keepingCapacity: true)
        return result
    }

    private func route(_ outcome: PapyrusRunOutcome) {
        switch outcome {
        case let .suspended(call):
            enqueue(call)
        case .completed, .faulted:
            terminal.append(outcome)
        }
    }

    private func enqueue(_ call: SuspendedCall) {
        let wake: Wake = switch call.request {
        case let .realSeconds(seconds):
            .realSeconds(realSeconds + max(0, seconds))
        case let .gameHours(hours):
            .gameHours(elapsedGameHours + max(0, hours))
        }
        entries.append(Entry(order: nextOrder, wake: wake, call: call))
        nextOrder &+= 1
        pendingCount = entries.count
    }

    private func consumeGameTime(_ gameClock: GameClock?) {
        guard let current = gameClock?.totalGameSeconds else { return }
        defer { lastGameSeconds = current }
        guard let previous = lastGameSeconds else { return }
        let hours = (current - previous) / GameClock.secondsPerHour
        elapsedGameHours += min(max(0, hours), maximumGameHoursPerStep)
    }

    private func wakeDueCalls() {
        while true {
            let due = entries
                .filter { isDue($0.wake) }
                .sorted { $0.order < $1.order }
            guard !due.isEmpty else {
                pendingCount = entries.count
                return
            }
            let dueOrders = Set(due.map(\.order))
            entries.removeAll { dueOrders.contains($0.order) }
            for entry in due {
                route(runtime.resume(entry.call))
            }
        }
    }

    private func isDue(_ wake: Wake) -> Bool {
        switch wake {
        case let .realSeconds(value):
            realSeconds >= value
        case let .gameHours(value):
            elapsedGameHours >= value
        }
    }
}
