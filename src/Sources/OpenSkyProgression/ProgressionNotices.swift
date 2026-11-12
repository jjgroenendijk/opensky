// The HUD notices and story events that skill and level progress raise.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// Part of `ProgressionCoordinator`: queues the notices the app runs once a frame.
@MainActor
final class ProgressionNotices {
    let texts: ProgressionTexts
    /// Takes `SKIL` and `LEVL`.
    private weak let storyEvents: (any StoryEventReporting)?
    private var pending: [ProgressionCommand] = []
    /// Earned levels the HUD has announced, so each shows its notice once.
    private var announcedLevelsReady = 0

    init(texts: ProgressionTexts, storyEvents: (any StoryEventReporting)?) {
        self.texts = texts
        self.storyEvents = storyEvents
    }

    func take() -> [ProgressionCommand] {
        defer { pending = [] }
        return pending
    }

    func show(_ text: String) {
        pending.append(.showNotification(text))
    }

    func incrementStat(_ name: String) {
        pending.append(.incrementStat(name))
    }

    func report(_ report: SkillAdvanceReport, skillName: String) {
        if report.didAdvance {
            storyEvents?.reportStoryEvent(.skillIncrease(skill: report.skill))
            show(texts.skillIncreasedText(skill: skillName, level: Int(report.level)))
        }
        if let levelUp = report.levelUp {
            reportLevel(levelUp)
        }
    }

    /// The level-up notice shows once per level earned, not once per skill point
    /// banked while the level waits.
    func reportLevel(_ report: PlayerLevelUpReport) {
        if report.didLevel {
            storyEvents?.reportStoryEvent(.levelIncrease(level: report.level))
        }
        if report.levelsReady > announcedLevelsReady {
            show(texts.levelUpAvailable)
        }
        announcedLevelsReady = report.levelsReady
    }
}
