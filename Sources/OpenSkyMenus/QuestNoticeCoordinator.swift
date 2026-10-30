// Shows the HUD notices of quest changes: the quest's title over `sHUDStarted`,
// `sHUDCompleted`, or `sHUDFailed`, and each new objective as a line. Which change
// shows which text is OpenSky's reading (docs/engine/journal.md#hud-notices).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

/// The status line under a quest title.
nonisolated public enum QuestNoticeText: String, GameSettingTextKey {
    case started = "sHUDStarted"
    case completed = "sHUDCompleted"
    case failed = "sHUDFailed"

    public var fallback: String {
        switch self {
        case .started: "Started"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

public final class QuestNoticeCoordinator {
    private let hud: HUDCoordinator
    private let texts: () -> GameSettingTexts<QuestNoticeText>
    private var tracker = QuestNoticeTracker()
    private var seenRevision: UInt64?

    public init(hud: HUDCoordinator, texts: @escaping () -> GameSettingTexts<QuestNoticeText>) {
        self.hud = hud
        self.texts = texts
    }

    /// Forgets every quest, so a loaded save announces nothing.
    public func reset() {
        tracker.reset()
        seenRevision = nil
    }

    /// Compares the quests when `revision` moved since the last call.
    public func update(
        runtime: any QuestAccess,
        quests readQuests: @autoclosure () -> [(quest: Quest, state: QuestRuntimeState)],
        revision: UInt64, strings: LocalizedStrings?,
        aliases readAliases: @autoclosure () -> QuestAliasNaming = .none
    ) {
        guard revision != seenRevision else { return }
        seenRevision = revision
        let quests = readQuests()
        let aliases = readAliases()
        let texts = texts()
        let byID = Dictionary(quests.map { ($0.quest.formID, $0) }) { first, _ in first }
        for notice in tracker.notices(in: quests) {
            guard let (quest, state) = byID[notice.quest] else { continue }
            let entry = JournalMenuModel.makeEntry(
                quest: quest, state: state,
                strings: strings?.scoped(to: runtime.quests.sourcePlugin(of: quest.formID)),
                aliases: aliases
            )
            show(notice, entry: entry, texts: texts)
        }
    }

    private func show(
        _ notice: QuestNotice, entry: JournalQuestEntry, texts: GameSettingTexts<QuestNoticeText>
    ) {
        switch notice {
        case .started:
            hud.showBigNotice(HUDBigNotice(
                title: entry.title, status: texts[.started], sound: "UIQuestNew"
            ))
        case .completed:
            hud.showBigNotice(HUDBigNotice(
                title: entry.title, status: texts[.completed], sound: "UIQuestComplete"
            ))
        case .failed:
            hud.showBigNotice(HUDBigNotice(title: entry.title, status: texts[.failed]))
        case let .objectiveShown(_, objective):
            guard let line = entry.objectives.first(where: { $0.index == objective }) else {
                return
            }
            hud.showNotification(line.text, sound: "UIObjectiveNew")
        }
    }
}
