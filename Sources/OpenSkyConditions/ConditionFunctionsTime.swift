// Time-reading condition functions. They read the game clock, never a wall clock,
// so the same clock gives the same answer.

import Foundation
import OpenSkyWorldState

nonisolated extension ConditionFunctions {
    public static func installTime(_ registry: inout ConditionFunctionRegistry) {
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

    /// Game time as a decimal hour in [0, 24): 4:30am is 4.5 (Creation Kit wiki
    /// "GetCurrentTime"). Without a clock it reads the plugin's `GameHour` default.
    public static func currentTime(_ call: ConditionCall) -> Result<Float, ConditionFailure> {
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

    /// Weekday of the vanilla start date, 17th of Last Seed 4E 201: a Sundas
    /// (<https://en.uesp.net/wiki/Skyrim:Calendar>). A weekday carried over from an
    /// earlier save is not modelled.
    public static let vanillaStartWeekday = 0

    /// Day of the week, 0 = Sundas through 6 = Loredas (<https://ck.uesp.net/wiki/GetDayOfWeek>).
    /// The 365-day year has no leap day. Counted from the documented start date via
    /// `GameClock.daysPassed`, because the epoch's weekday is unknown.
    public static func dayOfWeek(of clock: GameClock) -> Int {
        let days = Int(clock.daysPassed.rounded(.down))
        return (((days + vanillaStartWeekday) % 7) + 7) % 7
    }

    /// The seven day names, in `dayOfWeek(of:)` order (UESP `Lore:Calendar`).
    public static let weekdayNames = [
        "Sundas", "Morndas", "Tirdas", "Middas", "Turdas", "Fredas", "Loredas"
    ]
}
