// Update-timer registry for `Form.RegisterForUpdate` and friends (issue
// #277): per-instance timers that fire `OnUpdate` / `OnUpdateGameTime`
// through the world event queue.
//
// The registry is a peer of `PapyrusScheduler`, not part of it: a scheduler
// entry carries a suspended continuation, while a timer carries nothing but
// an interval and a slot. Both share the same fixed-step policy — real time
// counts whole ticks so `Double(n) * fixedStepSeconds` is one rounding step,
// and game time accumulates capped, never-negative hour deltas from the
// sampled `GameClock`.
//
// Slot semantics, resolving what the Creation Kit wiki leaves unstated:
//
// * Four independent slots per instance: {real, game-time} x {repeating,
//   single-shot}. Registering into a slot replaces that slot only; the wiki
//   states this for the real-time family and the game-time family follows by
//   symmetry.
// * `UnregisterForUpdate()` clears both real-time slots and
//   `UnregisterForUpdateGameTime()` clears both game-time slots; the families
//   never affect each other.
// * A non-finite, zero, or negative interval clamps to zero: a single-shot
//   fires on the next fixed step and a repeating timer fires once per step.
// * Scrub avalanche rule: a due timer fires at most once per step. A
//   repeating timer re-anchors to "now" after firing rather than queueing
//   per-elapsed-interval catch-ups, so a capped 24-game-hour jump cannot
//   burst-fire one timer.

import Foundation

/// Which clock a timer counts against.
nonisolated enum PapyrusUpdateTimerFamily: Hashable, Sendable {
    case real
    case gameTime
}

/// One of the four per-instance timer slots. The raw value is the stable slot
/// order snapshots sort by.
nonisolated enum PapyrusUpdateTimerSlot: Int, CaseIterable, Hashable, Sendable {
    case realRepeating = 0
    case realSingleShot = 1
    case gameTimeRepeating = 2
    case gameTimeSingleShot = 3

    var family: PapyrusUpdateTimerFamily {
        switch self {
        case .realRepeating, .realSingleShot: .real
        case .gameTimeRepeating, .gameTimeSingleShot: .gameTime
        }
    }

    var isRepeating: Bool {
        self == .realRepeating || self == .gameTimeRepeating
    }
}

/// One persisted timer slot, the unit stage B's save chunk serializes. The
/// delay is stored as time remaining rather than an absolute deadline, so a
/// restore re-anchors against the current clock and the wall or game time
/// spent between save and load never counts toward the timer.
nonisolated struct PapyrusTimerState: Equatable, Sendable {
    let key: PapyrusInstanceKey
    let slot: PapyrusUpdateTimerSlot
    /// Registered interval in the slot's unit: real seconds or game hours.
    let interval: Double
    /// Time left before the next fire, in the same unit. Never negative.
    let remaining: Double
}

/// The timer table itself: slots keyed by instance, plus the clock anchors.
nonisolated struct PapyrusUpdateTimerRegistry {
    /// When one armed slot is due, in the arithmetic of its family.
    private enum Wake: Equatable {
        case realSteps(startTick: Int, duration: Double)
        case gameHours(deadline: Double)
    }

    private struct Entry: Equatable {
        let interval: Double
        var wake: Wake
        let order: UInt64
    }

    /// One due slot, in registration order among slots due the same step.
    struct Firing: Equatable {
        let key: PapyrusInstanceKey
        let slot: PapyrusUpdateTimerSlot
    }

    /// Same forward cap as `PapyrusScheduler.maximumGameHoursPerStep`: one
    /// step's game-time contribution never exceeds a day, so a console scrub
    /// cannot flush every game-time timer through years at once.
    let maximumGameHoursPerStep: Double

    private(set) var tickCount = 0
    private(set) var elapsedGameHours = 0.0
    private var lastGameSeconds: Double?
    private var nextOrder: UInt64 = 0
    private var entries: [PapyrusInstanceKey: [PapyrusUpdateTimerSlot: Entry]] = [:]

    init(maximumGameHoursPerStep: Double = 24) {
        self.maximumGameHoursPerStep = max(0, maximumGameHoursPerStep)
    }

    var pendingCount: Int {
        entries.values.reduce(0) { $0 + $1.count }
    }

    /// Arms `slot` on `key`, replacing whatever that slot held.
    mutating func register(
        key: PapyrusInstanceKey,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    ) {
        let clamped = Self.clamp(interval)
        arm(key: key, slot: slot, interval: clamped, delay: clamped)
    }

    /// Re-arms a restored slot with its saved remaining delay, anchored to
    /// the current tick and game-hour counters.
    mutating func restore(
        key: PapyrusInstanceKey,
        slot: PapyrusUpdateTimerSlot,
        interval: Double,
        remaining: Double
    ) {
        arm(
            key: key,
            slot: slot,
            interval: Self.clamp(interval),
            delay: Self.clamp(remaining)
        )
    }

    /// Clears both of `family`'s slots on `key`, leaving the other family
    /// untouched.
    mutating func unregister(
        key: PapyrusInstanceKey,
        family: PapyrusUpdateTimerFamily
    ) {
        guard var slots = entries[key] else { return }
        for slot in PapyrusUpdateTimerSlot.allCases where slot.family == family {
            slots[slot] = nil
        }
        entries[key] = slots.isEmpty ? nil : slots
    }

    /// Drops every slot `key` holds; called when the instance is retired.
    mutating func removeAll(for key: PapyrusInstanceKey) {
        entries[key] = nil
    }

    /// Advances one fixed step and returns the slots that came due, ordered
    /// by registration order. Each due slot appears exactly once: a repeating
    /// slot re-anchors to now plus its interval, a single-shot clears.
    mutating func advanceStep(
        stepSeconds: Double,
        gameClock: GameClock?
    ) -> [Firing] {
        tickCount += 1
        consumeGameTime(gameClock)
        let due = dueEntries(stepSeconds: stepSeconds)
        for (_, firing) in due {
            settle(firing)
        }
        return due.sorted { $0.order < $1.order }.map(\.firing)
    }

    /// Persistable view of every slot whose instance is in `keys`, sorted by
    /// instance key then slot raw value for deterministic save output.
    func states(
        for keys: Set<PapyrusInstanceKey>,
        stepSeconds: Double
    ) -> [PapyrusTimerState] {
        entries.keys.filter(keys.contains).sorted().flatMap { key in
            (entries[key] ?? [:])
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { slot, entry in
                    PapyrusTimerState(
                        key: key,
                        slot: slot,
                        interval: entry.interval,
                        remaining: remaining(entry.wake, stepSeconds: stepSeconds)
                    )
                }
        }
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }

    private mutating func arm(
        key: PapyrusInstanceKey,
        slot: PapyrusUpdateTimerSlot,
        interval: Double,
        delay: Double
    ) {
        let wake: Wake = switch slot.family {
        case .real:
            .realSteps(startTick: tickCount, duration: delay)
        case .gameTime:
            .gameHours(deadline: elapsedGameHours + delay)
        }
        entries[key, default: [:]][slot] = Entry(
            interval: interval, wake: wake, order: nextOrder
        )
        nextOrder &+= 1
    }

    /// Same sampling policy as `PapyrusScheduler.consumeGameTime`: the first
    /// sample only anchors, a backward jump contributes zero and re-anchors,
    /// and one step's forward contribution is capped.
    private mutating func consumeGameTime(_ gameClock: GameClock?) {
        guard let current = gameClock?.totalGameSeconds else { return }
        defer { lastGameSeconds = current }
        guard let previous = lastGameSeconds else { return }
        let hours = (current - previous) / GameClock.secondsPerHour
        elapsedGameHours += min(max(0, hours), maximumGameHoursPerStep)
    }

    private func dueEntries(
        stepSeconds: Double
    ) -> [(order: UInt64, firing: Firing)] {
        var due: [(order: UInt64, firing: Firing)] = []
        for (key, slots) in entries {
            for (slot, entry) in slots
                where isDue(entry.wake, stepSeconds: stepSeconds)
            {
                due.append((entry.order, Firing(key: key, slot: slot)))
            }
        }
        return due
    }

    private mutating func settle(_ firing: Firing) {
        guard var slots = entries[firing.key] else { return }
        if firing.slot.isRepeating, let fired = slots[firing.slot] {
            let wake: Wake = switch firing.slot.family {
            case .real:
                .realSteps(startTick: tickCount, duration: fired.interval)
            case .gameTime:
                .gameHours(deadline: elapsedGameHours + fired.interval)
            }
            slots[firing.slot] = Entry(
                interval: fired.interval, wake: wake, order: fired.order
            )
        } else {
            slots[firing.slot] = nil
        }
        entries[firing.key] = slots.isEmpty ? nil : slots
    }

    private func isDue(_ wake: Wake, stepSeconds: Double) -> Bool {
        switch wake {
        case let .realSteps(startTick, duration):
            Double(tickCount - startTick) * stepSeconds >= duration
        case let .gameHours(deadline):
            elapsedGameHours >= deadline
        }
    }

    private func remaining(_ wake: Wake, stepSeconds: Double) -> Double {
        switch wake {
        case let .realSteps(startTick, duration):
            max(0, duration - Double(tickCount - startTick) * stepSeconds)
        case let .gameHours(deadline):
            max(0, deadline - elapsedGameHours)
        }
    }
}

extension PapyrusWorldRuntime {
    /// Arms one timer slot on the exact script instance behind `handle`.
    /// An opaque (non-scripted) handle has no instance to deliver `OnUpdate`
    /// to, so the call is a no-op; the native still returns None either way,
    /// matching a registration the engine accepted but can never deliver.
    @discardableResult
    func registerUpdateTimer(
        handle: PapyrusObjectHandle,
        slot: PapyrusUpdateTimerSlot,
        interval: Double
    ) -> Bool {
        guard let key = keysByHandle[handle] else { return false }
        updateTimers.register(key: key, slot: slot, interval: interval)
        return true
    }

    /// Clears both of `family`'s slots on the instance behind `handle`.
    @discardableResult
    func unregisterUpdateTimers(
        handle: PapyrusObjectHandle,
        family: PapyrusUpdateTimerFamily
    ) -> Bool {
        guard let key = keysByHandle[handle] else { return false }
        updateTimers.unregister(key: key, family: family)
        return true
    }

    /// Advances the timer table one fixed step and enqueues one event per due
    /// slot — never dispatched inline, so a handler that re-registers cannot
    /// re-enter dispatch. Runs between the scheduler tick and the queue drain,
    /// so a timer becoming due on step N dispatches on step N.
    func advanceUpdateTimers(gameClock: GameClock?) {
        let firings = updateTimers.advanceStep(
            stepSeconds: fixedStepSeconds, gameClock: gameClock
        )
        for firing in firings {
            enqueue(PapyrusScriptEvent(
                target: firing.key,
                functionName: firing.slot.family == .real
                    ? Self.onUpdateEventName
                    : Self.onUpdateGameTimeEventName,
                arguments: [],
                activationDepth: 0
            ))
        }
    }
}
