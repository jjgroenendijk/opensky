// The date line the wait and map menus show.

import Foundation
@testable import OpenSkyWorldState
import Testing

struct GameClockMenuTextTests {
    @Test func theVanillaStartReadsAsASundasAfternoon() {
        #expect(GameClock().menuDateText == "Sundas, 1:00 PM, 17th of Last Seed, 4E 201")
    }

    @Test func midnightAndNoonReadAsTwelve() {
        var clock = GameClock()
        clock.setHour(0.5)
        #expect(clock.menuDateText.hasPrefix("Sundas, 12:30 AM"))
        clock.setHour(12)
        #expect(clock.menuDateText.hasPrefix("Sundas, 12:00 PM"))
    }

    @Test func ordinalsFollowEnglish() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 31].map(GameClock.ordinal) == [
            "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "31st"
        ])
    }
}
