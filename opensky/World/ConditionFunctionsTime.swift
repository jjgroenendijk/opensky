// Time-reading condition functions (issue #251), split out of
// `ConditionFunctions` the way `AS2NativesMath` splits out of `AS2Natives`.
//
// Both read the game clock rather than any wall clock, so a condition list
// evaluated twice against the same clock answers the same way.

import Foundation

nonisolated extension ConditionFunctions {
    static func installTime(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 18,
            name: "GetCurrentTime"
        ) { call in
            Self.currentTime(call)
        })

        registry.register(ConditionFunction(
            index: 170,
            name: "GetDayOfWeek"
        ) { call in
            call.clock().map { Float(Self.dayOfWeek(of: $0)) }
        })
    }

    /// Current game time as a decimal hour in [0, 24) — 4:30am is 4.5
    /// (Creation Kit wiki "GetCurrentTime").
    ///
    /// The clock is the source of truth. A context with no clock still answers
    /// when the plugin's `GameHour` global is readable, because
    /// `GlobalResolution` projects that global from a clock when it has one and
    /// falls back to the plugin default when it does not.
    static func currentTime(_ call: ConditionCall) -> Result<Float, ConditionFailure> {
        if case let .success(clock) = call.clock() {
            return .success(clock.hourOfDay)
        }
        guard
            let hour = call.context.globals.floatValue(
                editorID: GameClock.TimeGlobal.gameHour.editorID
            )
        else {
            return .failure(.unavailableClock)
        }
        return .success(hour)
    }

    /// Day of the week, 0 = Sundas (Sunday) through 6 = Loredas (Saturday),
    /// per the seven day names in UESP `Lore:Calendar`.
    ///
    /// The Tamriel year is 365 days and has no leap day, so weekdays advance
    /// one per day and drift against the calendar year exactly as they do in
    /// the lore. Which weekday the clock epoch (4E 0, 1st of Morning Star)
    /// falls on is *not* documented on any source consulted, so OpenSky anchors
    /// it to Sundas and flags the anchor for verification against real game
    /// behaviour in the issue #251 sweep. Every relative answer — "two days
    /// later is two weekdays later" — is correct regardless of the anchor.
    static func dayOfWeek(of clock: GameClock) -> Int {
        let days = Int((clock.totalGameSeconds / GameClock.secondsPerDay).rounded(.down))
        return ((days % 7) + 7) % 7
    }

    /// The seven day names, in `dayOfWeek(of:)` order (UESP `Lore:Calendar`).
    static let weekdayNames = [
        "Sundas", "Morndas", "Tirdas", "Middas", "Turdas", "Fredas", "Loredas"
    ]
}
