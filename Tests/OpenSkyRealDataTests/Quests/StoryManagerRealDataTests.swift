// The story manager and the `.seq` session-start pass against the user's install.
// Pins were observed on 2026-10-03 against the shipped Skyrim SE masters and the
// free Creation Club plugins. See docs/engine/story-manager.md.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct StoryManagerRealDataTests {
    /// Quests per `.seq` file, for each plugin of the install that has one.
    private static let expectedListCounts: [String: Int] = [
        "Skyrim.esm": 330, "Update.esm": 3, "Dawnguard.esm": 51, "HearthFires.esm": 7,
        "Dragonborn.esm": 30, "ccBGSSSE001-Fish.esm": 10, "ccBGSSSE025-AdvDSGS.esm": 5
    ]
    /// The first quest that `Skyrim.seq` lists.
    private static let firstStartedQuest = "CreatureDialogueWerewolf"
    /// `ESJA`, jail escape, starts both quests under its tree with no conditions failing.
    private static let escapeQuests = ["EscapeJailAchievementQuest", "EscapeJailQuest"]

    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func sessionStartReadsEverySeqFile() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let data = StoryData.load(plugins: plugins)
        let files = VirtualFileSystem(root: root)
        let lists = data.plugins.map {
            PluginQuestList.load(plugin: $0.name, masters: $0.masters, files: files)
        }
        for (plugin, count) in Self.expectedListCounts {
            let list = try #require(
                lists.first { $0.plugin == plugin }?.list,
                "\(plugin) has no list"
            )
            #expect((try? list.get())?.quests.count == count, "\(plugin) list drift")
        }

        let runtime = QuestRuntime(store: WorldStateStore(), quests: QuestStore(plugins: plugins))
        let report = runtime.runSessionStart(lists: lists, starter: nil)
        // The quest store indexes every active plugin, so every listed quest starts.
        #expect(report.startedCount == Self.expectedListCounts.values.reduce(0, +))
        for entry in report.entries {
            #expect(entry.outcome == .started, "\(entry.plugin) \(entry.quest)")
        }
        #expect(report.entries.first?.editorID == Self.firstStartedQuest)
        #expect(report.brokenLists.isEmpty)
        #expect(runtime.runSessionStart(lists: lists, starter: nil).startedCount == 0)
    }

    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func jailEscapeEventStartsItsQuests() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let quests = QuestStore(file: file, pluginName: "Skyrim.esm")
        let store = WorldStateStore()
        let story = StoryManagerRuntime(
            store: store,
            quests: QuestRuntime(store: store, quests: quests),
            story: StoryManagerStore(plugins: [(name: "Skyrim.esm", file: file)]),
            context: ConditionContext(subject: .player),
            registry: .standard
        )
        var event = StoryEventData(event: "ESJA")
        event.actor1 = .player
        let walk = story.fire(event)

        #expect(walk.startedQuests.compactMap { quests.quest($0)?.editorID } == Self.escapeQuests)
        #expect(walk.tally.failureTotal == 0)
        for quest in walk.startedQuests {
            #expect(story.state(of: quest)?.startCount == 1)
        }
        // A second fire finds both quests running, so it starts nothing.
        #expect(story.fire(event).startedQuests.isEmpty)
    }
}
