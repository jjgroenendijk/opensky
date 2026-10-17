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

    public static let vanillaStartWeekday = GameClock.vanillaStartWeekday

    public static func dayOfWeek(of clock: GameClock) -> Int {
        clock.weekday
    }

    /// The seven day names, in `dayOfWeek(of:)` order (UESP `Lore:Calendar`).
    public static let weekdayNames = [
        "Sundas", "Morndas", "Tirdas", "Middas", "Turdas", "Fredas", "Loredas"
    ]
}
