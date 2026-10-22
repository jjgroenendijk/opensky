// Lines an NPC says on its own: a force greet and the combat lines, each held back by
// its `SpeechTimerSettings` wait. See docs/engine/dialogue.md#speech-timers.

import OpenSkyConditions
import OpenSkyFormatsESM

extension DialogueCoordinator {
    /// True when `speaker` may force greet now, which starts its `fAIForceGreetingTimer`.
    public func claimForceGreet(speaker: ReferenceKey, now: Double) -> Bool {
        guard speechClock.isReady(.forceGreeting, speaker: speaker, now: now) else {
            return false
        }
        speechClock.note(
            .forceGreeting, speaker: speaker, now: now,
            wait: speechTimers.wait(after: .forceGreeting, unit: 0)
        )
        return true
    }

    /// The combat line `speaker` says now, recorded as said, or nil when its window has
    /// not passed, the chance roll fails, or no topic of the line's subtype passes.
    public func combatLine(
        _ line: NPCSpeechLine, speaker: ReferenceKey, now: Double
    ) -> FormID? {
        guard
            let subtype = line.subtype,
            speechClock.isReady(line, speaker: speaker, now: now),
            Float(speechRandom.percent()) < speechTimers.chance(of: line) * 100,
            let selection = runtime?.topics(subtype: subtype, speaker: speaker),
            let info = sayAlone(selection, speaker: speaker)
        else { return nil }
        let unit = Float(speechRandom.percent()) / 99
        speechClock.note(
            line, speaker: speaker, now: now, wait: speechTimers.wait(after: line, unit: unit)
        )
        return info
    }
}
