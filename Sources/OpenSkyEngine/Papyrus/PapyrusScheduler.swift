// Deterministic fixed-step scheduling for latent native continuations.

import Foundation

nonisolated final class PapyrusScheduler {
    private struct Entry {
        let order: UInt64
        let wake: Wake
        let call: SuspendedCall
    }

    /// Real-time wakes count whole ticks since enqueue rather than comparing
    /// accumulated seconds: `Double(n) * fixedStepSeconds` is computed in one
    /// rounding step, so `Utility.Wait(1.0)` at a 1/30 step wakes after exactly
    /// 30 ticks, where an accumulated `realSeconds` drifts past 31.
    private enum Wake {
        case realSteps(startTick: Int, duration: Double)
        case gameHours(Double)
    }

    let runtime: PapyrusRuntime
    let fixedStepSeconds: Double
    let maximumGameHoursPerStep: Double

    /// Observation seam for the M11.2 world runtime: called after every woken
    /// call resumes, before its outcome is routed, so the caller can retire
    /// per-instance bookkeeping and count resumes.
    var onResume: ((SuspendedCall, PapyrusRunOutcome) -> Void)?

    private(set) var tickCount = 0
    private(set) var elapsedGameHours = 0.0
    private(set) var pendingCount = 0

    var realSeconds: Double {
        Double(tickCount) * fixedStepSeconds
    }

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
        tickCount += 1
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
            .realSteps(startTick: tickCount, duration: max(0, seconds))
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
                let outcome = runtime.resume(entry.call)
                onResume?(entry.call, outcome)
                route(outcome)
            }
        }
    }

    private func isDue(_ wake: Wake) -> Bool {
        switch wake {
        case let .realSteps(startTick, duration):
            Double(tickCount - startTick) * fixedStepSeconds >= duration
        case let .gameHours(value):
            elapsedGameHours >= value
        }
    }
}
