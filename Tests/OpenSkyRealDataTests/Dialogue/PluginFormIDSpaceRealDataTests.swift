// Records from a plugin that loads later than its own master index says. Dragonborn
// writes its own forms as 0x02xxxxxx but loads fifth, so read raw they name nothing.
// Run with `make test-real T='PluginFormIDSpaceRealDataTests'`.

import FeaturesTesting
import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct PluginFormIDSpaceRealDataTests {
    private static let dragonborn = "Dragonborn.esm"
    /// `GetQuestRunning`, `GetStage`, `GetStageDone`, and `GetQuestCompleted`.
    private static let questFunctions: Set<UInt16> = [56, 58, 59, 543]

    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aDragonbornQuestConditionReadsTheDragonbornQuestItNames() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let quests = try QuestStore(plugins: VanillaMasters.load(root: root))
        var context = ConditionContext()
        context.quests = QuestRuntime(store: WorldStateStore(), quests: quests).resolution()
        var checked = 0
        for quest in quests.sortedQuests()
            where quests.sourcePlugin(of: quest.formID) == Self.dragonborn
        {
            let source = quests.sourceResolver(of: quest.formID)
            var translated = context
            translated.formIDTranslation = quests.translation(of: quest.formID)
            for condition in Self.conditions(of: quest)
                where Self.questFunctions.contains(condition.functionIndex)
                && source.resolve(condition.parameter1.asFormID)?.plugin == Self.dragonborn
            {
                checked += 1
                var raw = ConditionEvaluator(context: context, registry: .standard)
                var own = ConditionEvaluator(context: translated, registry: .standard)
                #expect(Self.missesQuest(raw.evaluate(condition)), "\(quest.editorID ?? "")")
                #expect(!Self.missesQuest(own.evaluate(condition)), "\(quest.editorID ?? "")")
            }
        }
        #expect(checked > 0)
    }

    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aDLCSceneSpeaksItsDialogueLine() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        let quests = QuestStore(plugins: plugins)
        let scenes = try #require(StoryData.load(plugins: plugins).scenes)
        let catalog = SceneCatalog(store: scenes, resolver: quests.resolver)
        let dialogue = DialogueStore(plugins: plugins)
        let dlcScenes = scenes.scenes.records.filter { record in
            record.sourcePlugin != VanillaMasters.names[0] && record.record.actions.contains {
                if case .dialogue = $0.payload {
                    return true
                }
                return false
            }
        }
        let spoken = dlcScenes.lazy.compactMap { record in
            quests.resolver.localFormID(of: record.id).flatMap { catalog.scene($0) }
        }.first { Self.speaksADLCLine($0, catalog: catalog, quests: quests, dialogue: dialogue) }
        #expect(!dlcScenes.isEmpty)
        #expect(spoken != nil, "no DLC scene of \(dlcScenes.count) spoke a DLC line")
    }

    /// Plays `entry` with its quest running and no loaded cell.
    @MainActor
    private static func speaksADLCLine(
        _ entry: CatalogScene,
        catalog: SceneCatalog,
        quests: QuestStore,
        dialogue: DialogueStore
    ) -> Bool {
        let store = WorldStateStore()
        let questRuntime = QuestRuntime(store: store, quests: quests)
        guard let quest = entry.quest, (try? questRuntime.startQuest(quest)) != nil else {
            return false
        }
        var context = ConditionContext()
        context.aliases = questRuntime.aliasResolution()
        var runtime = SceneRuntime(catalog: catalog, dialogue: DialogueRuntime(
            store: store,
            dialogue: dialogue,
            questStates: questRuntime.resolution(),
            context: context,
            registry: .standard
        ))
        guard var events = try? runtime.start(entry.formID) else { return false }
        while runtime.isPlaying(entry.formID), runtime.now < 120 {
            runtime.now += 1
            events += runtime.tick()
        }
        return events.contains { event in
            guard
                case let .line(line) = event.step,
                case let .plugin(name, _) = dialogue.key(forInfo: line.info)
            else {
                return false
            }
            return name != VanillaMasters.names[0].lowercased()
        }
    }

    private static func conditions(of quest: Quest) -> [Condition] {
        let lists = [quest.dialogueConditions, quest.storyManagerConditions]
            + quest.stages.flatMap { $0.logEntries.map(\.conditions) }
            + quest.objectives.flatMap { $0.targets.map(\.conditions) }
        return lists.flatMap(\.conditions)
    }

    private static func missesQuest(_ outcome: ConditionOutcome) -> Bool {
        outcome.failures.contains {
            if case .unresolvedQuest = $0 {
                return true
            }
            return false
        }
    }
}
