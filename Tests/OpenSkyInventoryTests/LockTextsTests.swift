// Lock words from the string settings, the Novice bound from `iLockLevelMaxVeryEasy`,
// and the notice a refused press shows.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import Testing

@MainActor
struct LockTextsTests {
    @Test func theSettingsNameTheBandsAndTheNoviceBound() throws {
        let store = try GameSettingFixture.store([
            "sLockLevelNameVeryEasy": .text("Easy as pie"),
            "sUnlock": .text("Pick"),
            "iLockLevelMaxVeryEasy": .integer(10)
        ])
        let texts = LockTexts.resolve(store: store) { text in
            guard case let .inline(value) = text else { return nil }
            return value
        }
        let settings = LockpickingSettings.resolve(store: store)
        #expect(settings.noviceMaximum == 10)
        let target = LockCoordinatorTests.door(level: .novice)
        let lock = ReferenceLockState(isLocked: true, level: 5, key: nil)
        let labelled = LockCore.labelled(
            target.interaction, lock: lock, texts: texts, noviceMaximum: settings.noviceMaximum
        )
        #expect(labelled.actionLabel == "Pick")
        #expect(labelled.name == "Fixture Door (Easy as pie)")
        #expect(texts.name(of: .master) == "Master")
        #expect(texts.requiresKey == "sImpossibleLock")
    }

    @Test func aRefusedPressExplainsWhyNoMinigameOpens() {
        let texts = LockTexts.vanilla
        #expect(LockCore.refusalNotice(for: .requiresKey, lockpicks: 3, texts: texts)
            == "sImpossibleLock")
        #expect(LockCore.refusalNotice(for: .adept, lockpicks: 0, texts: texts)
            == "sOutOfLockpicks")
        #expect(LockCore.refusalNotice(for: .adept, lockpicks: 1, texts: texts) == nil)
    }
}
