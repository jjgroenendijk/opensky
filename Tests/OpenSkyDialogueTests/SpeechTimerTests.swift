// The NPC speech waits and chances from `SpeechTimerSettings`, and the per-speaker clock
// that holds a line back until its wait has passed (docs/engine/dialogue.md#speech-timers).

import OpenSkyDialogue
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import Testing

struct SpeechTimerTests {
    private let guardKey = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
    private let bandit = ReferenceKey.plugin(name: "test.esm", objectID: 0x200)

    @Test func aForceGreetWaitsTheGreetingTimer() {
        var settings = SpeechTimerSettings.vanilla
        settings.forceGreetingSeconds = 4
        #expect(settings.wait(after: .forceGreeting, unit: 0.7) == 4)
    }

    @Test func aCombatLineWaitsAPointInTheAttackWindow() {
        let settings = SpeechTimerSettings.vanilla
        #expect(settings.wait(after: .combatAttack, unit: 0) == 5)
        #expect(settings.wait(after: .combatHit, unit: 1) == 10)
        #expect(settings.wait(after: .combatAttack, unit: 0.5) == 7.5)
        #expect(settings.wait(after: .combatAttack, unit: 3) == 10)
    }

    @Test func aSwappedWindowAndBadValuesStayUsable() {
        var settings = SpeechTimerSettings.vanilla
        settings.attackLineMinSeconds = 10
        settings.attackLineMaxSeconds = 5
        #expect(settings.wait(after: .combatAttack, unit: 0) == 5)
        settings.forceGreetingSeconds = -.infinity
        #expect(settings.wait(after: .forceGreeting, unit: 0) == 0)
        settings.attackLineChance = .nan
        #expect(settings.chance(of: .combatAttack) == 0)
        settings.hitLineChance = 2
        #expect(settings.chance(of: .combatHit) == 1)
        #expect(settings.chance(of: .forceGreeting) == 1)
    }

    @Test func theVoicePaddingLengthensALine() {
        var settings = SpeechTimerSettings.vanilla
        #expect(settings.padded(2) == 2.5)
        settings.voiceFilePadding = -1
        #expect(settings.padded(2) == 2)
    }

    @Test func theClockHoldsALineBackPerSpeakerAndKind() {
        var clock = NPCSpeechClock()
        #expect(clock.isReady(.forceGreeting, speaker: guardKey, now: 0))
        clock.note(.forceGreeting, speaker: guardKey, now: 10, wait: 3)
        #expect(!clock.isReady(.forceGreeting, speaker: guardKey, now: 12.9))
        #expect(clock.isReady(.forceGreeting, speaker: guardKey, now: 13))
        #expect(clock.isReady(.combatAttack, speaker: guardKey, now: 11))
        #expect(clock.isReady(.forceGreeting, speaker: bandit, now: 11))
        clock.reset()
        #expect(clock.isReady(.forceGreeting, speaker: guardKey, now: 11))
    }

    @Test func aNegativeWaitDoesNotMoveTheClockBack() {
        var clock = NPCSpeechClock()
        clock.note(.combatHit, speaker: bandit, now: 5, wait: -10)
        #expect(clock.isReady(.combatHit, speaker: bandit, now: 5))
        #expect(!clock.isReady(.combatHit, speaker: bandit, now: 4.9))
    }

    @Test func onlyCombatLinesNameATopicSubtype() {
        #expect(NPCSpeechLine.forceGreeting.subtype == nil)
        #expect(NPCSpeechLine.combatAttack.subtype == "ATCK")
        #expect(NPCSpeechLine.combatHit.subtype == "HIT_")
    }

    @Test func theReadoutNamesEachValue() {
        #expect(SpeechTimerSettings.vanilla.readout == "Speech timers: force greet 3.0 s · "
            + "combat line 5.0-10.0 s · attack 1% · hit 1% · voice gap 0.50 s")
    }
}
