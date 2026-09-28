// Matching a PACK schedule (PSDT) against the running game clock. The record
// shape lives with the parsers in OpenSkyFormatsESM; `GameClock` is runtime state.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated extension Package.Schedule {
    public func matches(_ clock: GameClock) -> Bool {
        guard hour >= 0 else { return matchesCalendar(clock) }
        let start = Int(hour) * 60 + max(Int(minute), 0)
        let duration = Int(durationMinutes)
        let currentMinute = clockMinute(clock)
        guard duration > 0 else {
            return currentMinute == start && matchesCalendar(clock)
        }
        let elapsed = (currentMinute - start + Self.minutesPerDay)
            % Self.minutesPerDay
        guard duration >= Self.minutesPerDay || elapsed < duration else { return false }
        let wrapsFromPreviousDay = currentMinute < start
            && start + duration > Self.minutesPerDay
        let calendarClock = wrapsFromPreviousDay
            ? GameClock(totalGameSeconds: clock.totalGameSeconds - GameClock.secondsPerDay)
            : clock
        return matchesCalendar(calendarClock)
    }

    /// Next daily start/end edge, bounded to one day. Calendar-only edges
    /// are covered by the runtime's interval reevaluation.
    public func minutesUntilBoundary(after clock: GameClock) -> Float? {
        guard hour >= 0 else { return nil }
        let now = clock.hourOfDay * 60
        let start = Float(Int(hour) * 60 + max(Int(minute), 0))
        var candidates = [Self.forwardMinutes(from: now, to: start)]
        if durationMinutes > 0, durationMinutes < UInt32(Self.minutesPerDay) {
            let end = Float((Int(start) + Int(durationMinutes)) % Self.minutesPerDay)
            candidates.append(Self.forwardMinutes(from: now, to: end))
        }
        return candidates.filter { $0 > 0 }.min()
    }

    private func matchesCalendar(_ clock: GameClock) -> Bool {
        let monthMatches = month < 0 || Int(month) == clock.month
        let dateMatches = date == 0 || Int(date) == clock.day
        return monthMatches && dateMatches && matchesWeekday(clock.packageWeekday)
    }

    private func matchesWeekday(_ weekday: Int) -> Bool {
        switch dayOfWeek {
        case -1: true
        case 0 ... 6: Int(dayOfWeek) == weekday
        case 7: (1 ... 5).contains(weekday)
        case 8: weekday == 0 || weekday == 6
        case 9: weekday == 1 || weekday == 3 || weekday == 5
        case 10: weekday == 2 || weekday == 4
        default: false
        }
    }

    private func clockMinute(_ clock: GameClock) -> Int {
        Int(clock.hourOfDay * 60) % Self.minutesPerDay
    }

    private static func forwardMinutes(from current: Float, to boundary: Float) -> Float {
        let delta = (boundary - current).truncatingRemainder(dividingBy: Float(minutesPerDay))
        return delta > 0 ? delta : delta + Float(minutesPerDay)
    }

    private static let minutesPerDay = 24 * 60
}

nonisolated extension GameClock {
    /// PACK PSDT weekday index: Sundas = 0 ... Loredas = 6. Skyrim normally
    /// begins on Sundas, 17th of Last Seed, 4E 201 (UESP Skyrim:Calendar).
    public var packageWeekday: Int {
        let days = Int(floor(Double(daysPassed)))
        return ((days % 7) + 7) % 7
    }
}
