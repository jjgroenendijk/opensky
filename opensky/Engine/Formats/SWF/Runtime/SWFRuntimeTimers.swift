// `setInterval`, `clearInterval`, `setTimeout`, and `clearTimeout` (milestone
// 8.3.2 phase 3).
//
// These four were the head of the phase-2 missing-API tally once fully
// qualified class names started resolving: `clearInterval` 1,204 hits,
// `setInterval` 796, and `invalidationIntervalID` 590 across the vanilla
// install. They are not a convenience — they are load-bearing. CLIK's
// `UIComponent.invalidate()` schedules its own `draw()` through
// `setInterval(this, "_validate", 1)`, so a component that cannot set an
// interval never lays itself out, never populates its text fields, and never
// becomes interactive.
//
// A timer here is measured in *ticks*, not wall-clock milliseconds. The
// millisecond argument is converted with the movie's own header `FrameRate`,
// and a timer fires from `SWFMovieRuntime.advance()` — the same explicit tick
// that moves a playhead. Nothing reads a clock, so the same tick sequence
// always produces the same frame, which is the determinism contract in
// docs/rendering/ui.md.
//
// `setInterval` is a Flash player built-in with no entry in the SWF
// specification; the two calling conventions below are the documented
// ActionScript 2 ones.

import Foundation

/// Timers a running movie scheduled, keyed by the id `setInterval` handed back.
nonisolated final class SWFRuntimeTimers {
    /// One scheduled callback.
    struct Entry: Equatable {
        let id: Int
        /// The function to call, or the receiver when `method` names one.
        let callee: AS2Value
        /// Method name for the `setInterval(object, "name", ms)` form.
        let method: String?
        let arguments: [AS2Value]
        /// Ticks between fires, at least 1.
        let period: Int
        /// Ticks left before the next fire.
        var remaining: Int
        /// False for `setTimeout`, which is removed after it fires once.
        let repeats: Bool
    }

    private(set) var entries: [Entry] = []
    private var nextID = 1
    /// Timers refused because the movie scheduled more than this. A runaway
    /// `setInterval` loop is counted rather than allowed to grow the list.
    private(set) var dropped = 0

    /// Live timers one movie may hold.
    static let maximumTimers = 256

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Schedules a timer and returns its id, or 0 when the list is full.
    func add(
        callee: AS2Value,
        method: String?,
        arguments: [AS2Value],
        period: Int,
        repeats: Bool
    ) -> Int {
        guard entries.count < SWFRuntimeTimers.maximumTimers else {
            dropped += 1
            return 0
        }
        let identifier = nextID
        nextID += 1
        let ticks = max(1, period)
        entries.append(
            Entry(
                id: identifier, callee: callee, method: method, arguments: arguments,
                period: ticks, remaining: ticks, repeats: repeats
            )
        )
        return identifier
    }

    @discardableResult
    func remove(id: Int) -> Bool {
        let before = entries.count
        entries.removeAll { $0.id == id }
        return entries.count != before
    }

    func removeAll() {
        entries.removeAll()
    }

    /// Advances every timer by one tick and returns the ones that came due, in
    /// id order so a frame is reproducible. A timer scheduled by a callback in
    /// this pass is not in the returned list and therefore cannot fire twice.
    func tick() -> [Entry] {
        var due: [Entry] = []
        var kept: [Entry] = []
        kept.reserveCapacity(entries.count)
        for var entry in entries {
            entry.remaining -= 1
            guard entry.remaining <= 0 else {
                kept.append(entry)
                continue
            }
            due.append(entry)
            if entry.repeats {
                entry.remaining = entry.period
                kept.append(entry)
            }
        }
        entries = kept
        return due.sorted { $0.id < $1.id }
    }
}

nonisolated extension SWFMovieRuntime {
    /// Milliseconds to ticks against the movie's declared frame rate. A rate the
    /// header never set, or an interval below one frame, still costs one tick —
    /// a zero-tick timer would fire forever inside a single `advance()`.
    func timerTicks(milliseconds: Double) -> Int {
        let rate = movie.frameRate > 0 ? Double(movie.frameRate) : 30
        guard milliseconds.isFinite, milliseconds > 0 else {
            return 1
        }
        let ticks = (milliseconds * rate / 1000).rounded()
        return max(1, Int(min(ticks, Double(SWFMovieRuntime.maximumTimerTicks))))
    }

    /// Fires every timer that came due this tick. Called from `advance()`, never
    /// from a clock.
    func fireDueTimers() {
        for entry in timers.tick() {
            fire(entry)
        }
    }

    private func fire(_ entry: SWFRuntimeTimers.Entry) {
        guard let function = resolveTimer(entry) else {
            timers.remove(id: entry.id)
            return
        }
        let receiver = entry.method == nil ? AS2Value.undefined : entry.callee
        runtime.invoke(.object(function), thisValue: receiver, arguments: entry.arguments)
        markDirty()
    }

    /// Both `setInterval` forms resolve here: a bare function, or a receiver
    /// plus a method name looked up at fire time, which is what lets a movie
    /// replace the method between fires.
    private func resolveTimer(_ entry: SWFRuntimeTimers.Entry) -> AS2Object? {
        guard let method = entry.method else {
            return entry.callee.functionValue
        }
        guard let receiver = entry.callee.objectValue else {
            return nil
        }
        if let found = receiver.lookup(method)?.property.value.functionValue {
            return found
        }
        guard let node = SWFDisplayObject.resolve(receiver) else {
            return nil
        }
        return member(method, of: node)?.functionValue
    }
}

nonisolated extension SWFRuntimeNatives {
    /// The four global timer functions.
    static func installTimers(_ runtime: AS2Runtime) {
        AS2Natives.method(runtime, on: runtime.globalObject, name: "setInterval") { context in
            try schedule(context, repeats: true)
        }
        AS2Natives.method(runtime, on: runtime.globalObject, name: "setTimeout") { context in
            try schedule(context, repeats: false)
        }
        for name in ["clearInterval", "clearTimeout"] {
            AS2Natives.method(runtime, on: runtime.globalObject, name: name) { context in
                guard let owner = movieRuntime(context) else {
                    return .boolean(false)
                }
                let identifier = try context.number(0)
                guard identifier.isFinite else {
                    return .boolean(false)
                }
                return .boolean(owner.timers.remove(id: Int(identifier)))
            }
        }
    }

    /// `setInterval(function, ms, …)` and `setInterval(object, "method", ms, …)`.
    /// The second form is the one CLIK uses, and it is distinguished by the
    /// second argument being a string.
    private static func schedule(_ context: AS2CallContext, repeats: Bool) throws -> AS2Value {
        guard let owner = movieRuntime(context) else {
            return .integer(0)
        }
        let callee = context.argument(0)
        var method: String?
        var intervalIndex = 1
        if case let .string(name) = context.argument(1) {
            method = name
            intervalIndex = 2
        }
        let milliseconds = try context.interpreter.toNumber(context.argument(intervalIndex))
        let identifier = owner.timers.add(
            callee: callee,
            method: method,
            arguments: Array(context.arguments.dropFirst(intervalIndex + 1)),
            period: owner.timerTicks(milliseconds: milliseconds),
            repeats: repeats
        )
        return .integer(identifier)
    }
}
