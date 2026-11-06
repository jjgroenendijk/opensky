// The rumble buses become motor strengths each frame (docs/engine/sound-mix.md#rumble).

import Foundation
import OpenSkyAudio
import Testing

struct SoundRumbleTests {
    @Test func levelsStayInRange() {
        #expect(SoundRumble(small: -1, big: 3) == SoundRumble(small: 0, big: 1))
    }

    @Test func motorsFollowTheLevelByTheirExponents() {
        let motors = SoundRumble(small: 0.25, big: 0.25).motors(powerAttack: false)
        #expect(abs(motors.small - pow(0.25, 0.4)) < 1e-5)
        #expect(abs(motors.big - 0.5) < 1e-5)
        #expect(SoundRumble.silent.motors(powerAttack: true) == .silent)
    }

    @Test func powerAttackShakesHarder() {
        let level = SoundRumble(small: 0.25, big: 0.25)
        let normal = level.motors(powerAttack: false)
        let power = level.motors(powerAttack: true)
        #expect(power.small > normal.small)
        #expect(abs(power.big - pow(0.25, 0.35)) < 1e-5)
    }
}
