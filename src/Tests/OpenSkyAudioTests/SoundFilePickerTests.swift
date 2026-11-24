// The game's file pick among a descriptor's files. No game data.

@testable import OpenSkyAudio
import Testing

struct SoundFilePickerTests {
    /// A roll of the file played last takes the next one, wrapping round to the first.
    @Test func aRepeatTakesTheNextFile() {
        #expect(SoundFilePicker.index(roll: 2, count: 4, last: 2) == 3)
        #expect(SoundFilePicker.index(roll: 3, count: 4, last: 3) == 0)
        #expect(SoundFilePicker.index(roll: 1, count: 4, last: 2) == 1)
        #expect(SoundFilePicker.index(roll: 0, count: 4, last: nil) == 0)
        #expect(SoundFilePicker.index(roll: 0, count: 1, last: 0) == 0)
    }
}
