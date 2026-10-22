// The NPC speech waits and chances from `SpeechTimerSettings`, and the per-speaker clock
// that holds a line back until its wait has passed (docs/engine/dialogue.md#speech-timers).

import Foundation
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
            + "hello 5.0 s (gap 2.5 s) · combat line 5.0-10.0 s · taunt 10-30 s · "
            + "attack 1% · hit 1% · taunt 1% · idle 10-20 s · comment 20 s · voice gap 0.50 s")
    }

    @Test func aHelloHoldsBackEveryOtherSpeakerForTheExclusiveGap() {
        let settings = SpeechTimerSettings.vanilla
        var clock = NPCSpeechClock()
        clock.note(
            .hello, speaker: guardKey, now: 0, wait: settings.wait(after: .hello, unit: 0),
            sharedWait: settings.sharedWait(after: .hello, unit: 0)
        )
        #expect(!clock.isReady(.hello, speaker: bandit, now: 2))
        #expect(clock.isReady(.hello, speaker: bandit, now: 2.5))
        #expect(!clock.isReady(.hello, speaker: guardKey, now: 4.9))
        #expect(clock.isReady(.hello, speaker: guardKey, now: 5))
    }

    @Test func idleChatterAndCommentsShareOneWait() {
        let settings = SpeechTimerSettings.vanilla
        #expect(settings.sharedWait(after: .idleChatter, unit: 1) == 20)
        #expect(settings.sharedWait(after: .knockOver, unit: 0) == 40)
        #expect(settings.sharedWait(after: .playerAction("PCSH"), unit: 0) == 20)
        #expect(settings.sharedWait(after: .combatTaunt, unit: 0) == nil)
        #expect(settings.sharedWait(after: .bump, unit: 0) == nil)
    }

    @Test func aSilentLineStaysInsideTheWindow() {
        let settings = SpeechTimerSettings.vanilla
        #expect(settings.silentLineSeconds(readingSeconds: 0.5) == 2)
        #expect(settings.silentLineSeconds(readingSeconds: 5) == 5)
        #expect(settings.silentLineSeconds(readingSeconds: 30) == 8)
        #expect(settings.silentLineSeconds(readingSeconds: .nan) == 2)
    }

    @Test func theTauntChanceIsPerSixtiethOfASecond() {
        let settings = SpeechTimerSettings.vanilla
        #expect(settings.tauntChance(over: 0) == 0)
        let oneSecond = settings.tauntChance(over: 1)
        #expect(abs(oneSecond - (1 - pow(0.99, 60))) < 1e-5)
        #expect(settings.tauntChance(over: 2) > oneSecond)
    }

    @Test func aWeakHitDoesNotSpeak() {
        let settings = SpeechTimerSettings.vanilla
        #expect(!settings.hitSpeaks(damage: 0.5, maximumHealth: 100))
        #expect(settings.hitSpeaks(damage: 1, maximumHealth: 100))
        #expect(settings.hitSpeaks(damage: 1, maximumHealth: 0))
        #expect(!settings.hitSpeaks(damage: 0, maximumHealth: 0))
    }

    @Test func theSceneRepeatWindowIsOrdered() {
        var settings = SpeechTimerSettings.vanilla
        #expect(settings.sceneRepeatPause == 10 ... 30)
        settings.sceneRepeatMinSeconds = 40
        #expect(settings.sceneRepeatPause == 30 ... 40)
    }

    @Test func eachLineNamesItsTopicSubtype() {
        #expect(NPCSpeechLine.hello.subtype == "HELO")
        #expect(NPCSpeechLine.combatTaunt.subtype == "TAUT")
        #expect(NPCSpeechLine.idleChatter.subtype == "IDLE")
        #expect(NPCSpeechLine.knockOver.subtype == "KNOO")
        #expect(NPCSpeechLine.bump.subtype == "ACAC")
        #expect(NPCSpeechLine.playerAction("PCSH").subtype == "PCSH")
    }
}
