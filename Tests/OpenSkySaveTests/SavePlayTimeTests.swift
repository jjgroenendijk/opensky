// The play time a save slot shows: hours and two-digit minutes.

@testable import OpenSkySave
import Testing

struct SavePlayTimeTests {
    @Test
    func showsHoursAndMinutes() {
        #expect(SavePlayTime.text(seconds: 0) == "0:00")
        #expect(SavePlayTime.text(seconds: 3 * 3600 + 5 * 60 + 59) == "3:05")
        #expect(SavePlayTime.text(seconds: 125 * 3600) == "125:00")
    }
}
