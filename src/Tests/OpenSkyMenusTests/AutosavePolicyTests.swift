// When opening the pause menu saves, and the save notices' fallback lines.

import Foundation
import OpenSkyGameData
import OpenSkyMenusInterface
import Testing

@MainActor
struct AutosavePolicyTests {
    private static func settings(pauseOption: Double) -> PlayerSettingsStore {
        let store = PlayerSettingsStore(persistence: nil)
        store.set(.saveOnPause, to: pauseOption)
        return store
    }

    @Test func pauseSavesOnceTheChosenMinutesHavePassed() {
        let policy = AutosavePolicy()
        let fiveMinutes = Self.settings(pauseOption: 0)
        let last = Date(timeIntervalSinceReferenceDate: 0)
        #expect(policy.pauseInterval(settings: fiveMinutes) == 300)
        #expect(policy.shouldSaveOnPause(settings: fiveMinutes, lastSave: nil, now: last))
        #expect(!policy.shouldSaveOnPause(
            settings: fiveMinutes, lastSave: last, now: last.addingTimeInterval(299)
        ))
        #expect(policy.shouldSaveOnPause(
            settings: fiveMinutes, lastSave: last, now: last.addingTimeInterval(300)
        ))
    }

    @Test func disabledPauseSavingNeverSaves() {
        let policy = AutosavePolicy()
        let disabled = Self.settings(pauseOption: Double(AutosavePolicy.timerMinutes.count - 1))
        #expect(policy.pauseInterval(settings: disabled) == nil)
        #expect(!policy.shouldSaveOnPause(settings: disabled, lastSave: nil, now: Date()))
    }

    @Test func eachSaveNoticeHasAFallbackLine() {
        #expect(SaveNoticeText.autosaving.fallback == "Autosaving")
        #expect(SaveNoticeText.quickloading.fallback == "Quickloading")
        #expect(SaveNoticeText.noSave.fallback == "There is no save to load.")
    }
}
