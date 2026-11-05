// A sound's rumble is clamped to the motors' range (docs/engine/sound-mix.md#rumble).

import OpenSkyAudio
import Testing

struct SoundRumbleTests {
    @Test func strengthsStayInRange() {
        let rumble = SoundRumble(small: -1, big: 3, seconds: -2)
        #expect(rumble == SoundRumble(small: 0, big: 1, seconds: 0))
    }
}
