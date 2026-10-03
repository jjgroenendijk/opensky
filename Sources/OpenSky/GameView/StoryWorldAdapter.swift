// App side of scenes and the story manager: builds the scene catalog, runs the
// session-start pass, starts quests with their scripts, ticks scenes, and turns
// deaths and location changes into story events. The rules live in the
// coordinators (docs/engine/scenes.md, docs/engine/story-manager.md).

import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

final class StoryWorldAdapter {
    unowned let game: GameViewController
    /// Quests the session-start pass started, whose stages wait for one script attach.
    private var deferredStarts: [FormID]?
    /// Nil until the first check; then the player's last known location, or none.
    private var lastPlayerLocation: ResolvedFormID??
    private var framesSinceLocationCheck = 0
    /// Frames between location checks, because each builds a condition context.
    static let locationCheckInterval = 30

    /// Scene playback over the dialogue runtime.
    lazy var scenes: SceneCoordinator = {
        let scenes = SceneCoordinator(dialogue: game.dialogue)
        scenes.attach(world: self)
        return scenes
    }()

    /// Story-manager events and the session-start pass.
    lazy var storyManager: StoryManagerCoordinator = {
        let storyManager = StoryManagerCoordinator()
        storyManager.attach(world: self)
        return storyManager
    }()

    init(game: GameViewController) {
        self.game = game
    }

    /// After `wireDialogue`, because scenes speak through the dialogue index.
    func wireStory(provider: any WorldDataProviding, renderer: Renderer) {
        let data = (provider as? StoryDataProviding)?.storyData ?? StoryData()
        let scripts = provider as? ScriptDataProviding
        if let store = data.scenes, let resolver = scripts?.scriptFormIDResolver {
            scenes.catalog = SceneCatalog(store: store, resolver: resolver)
        }
        storyManager.story = data.storyManager
        game.scripts.bridge?.story = self
        if let files = scripts?.scriptFileSystem {
            runSessionStart(lists: data.plugins.map {
                PluginQuestList.load(plugin: $0.name, masters: $0.masters, files: files)
            })
        }
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advancePreviousSystems?(delta)
            self?.scenes.tick()
            self?.checkPlayerLocation()
        }
    }

    /// Starts every listed quest, then attaches scripts once and runs the start-up stages.
    func runSessionStart(lists: [PluginQuestList]) {
        deferredStarts = []
        storyManager.runSessionStart(lists: lists)
        let started = deferredStarts ?? []
        deferredStarts = nil
        game.scripts.bridge?.attachRunningQuestScripts()
        for quest in started {
            finishStart(quest)
        }
    }

    /// `KILL`: killer, victim, the victim's location. Crime status and rank stay 0.
    func reportKill(victim: ReferenceKey, killer: ReferenceKey?) {
        var event = StoryEventData(event: "KILL")
        event.actor1 = killer
        event.actor2 = victim
        event.location1 = game.runtimeState.conditionContext().data.currentLocation(of: victim)
        storyManager.fire(event)
    }

    /// `CLOC` when the player's location changes: actor, old location, new location.
    private func checkPlayerLocation() {
        framesSinceLocationCheck += 1
        guard framesSinceLocationCheck >= Self.locationCheckInterval else { return }
        framesSinceLocationCheck = 0
        let current = game.runtimeState.conditionContext().data.currentLocation(of: .player)
        defer { lastPlayerLocation = .some(current) }
        guard let previous = lastPlayerLocation, previous != current else { return }
        var event = StoryEventData(event: "CLOC")
        event.actor1 = .player
        event.location1 = previous
        event.location2 = current
        storyManager.fire(event)
    }

    var questRuntime: QuestRuntime? {
        game.scripts.bridge?.questRuntime as? QuestRuntime
    }

    /// Sets the start-up stage through the bridge, so its fragments queue, then
    /// starts the quest's begin-on-start scenes.
    private func finishStart(_ quest: FormID) {
        if
            let runtime = questRuntime,
            let record = runtime.quests.quest(quest),
            let stage = record.stages.first(where: { $0.flags.contains(.startUpStage) }),
            let key = runtime.quests.key(for: quest)
        {
            _ = try? game.scripts.bridge?.setQuestStage(stage.index, for: key)
        }
        scenes.questDidStart(quest)
    }
}

extension StoryWorldAdapter: QuestStarting {
    func startQuest(_ quest: FormID, event: StoryEventData?) throws {
        guard let runtime = questRuntime else { throw QuestError.unknownQuest(quest) }
        try runtime.startQuest(quest, event: event)
        if deferredStarts != nil {
            deferredStarts?.append(quest)
            return
        }
        game.scripts.bridge?.attachRunningQuestScripts()
        finishStart(quest)
    }
}

extension StoryWorldAdapter: StoryManagerWorld {
    func conditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    var conditionRegistry: ConditionFunctionRegistry {
        .standard
    }

    var questStarter: (any QuestStarting)? {
        self
    }
}

extension StoryWorldAdapter: SceneWorld {
    var sceneFragments: (any SceneFragmentDispatching)? {
        game.scripts.bridge
    }

    var sceneSeconds: Double {
        guard let clock = game.renderer?.gameClock else { return 0 }
        let timescale = game.renderer?.currentTimescale ?? GameClock.defaultTimescale
        return clock.totalGameSeconds / Double(max(timescale, 1))
    }

    func lineDuration(of info: TopicInfo) -> Float {
        let strings = game.dialogue.strings
        return SceneCore.lineDuration(texts: info.responses.map { response in
            strings.flatMap { response.resolvedText(using: $0) }
        })
    }

    func stopQuest(_ quest: FormID) {
        guard let runtime = questRuntime, let key = runtime.quests.key(for: quest) else { return }
        try? game.scripts.bridge?.stopQuest(for: key)
    }
}

extension StoryWorldAdapter: PapyrusStoryBridge {
    func sendStoryEvent(_ event: StoryEventData) -> Bool {
        !(storyManager.fire(event)?.startedQuests.isEmpty ?? true)
    }

    func startScene(_ scene: FormID) -> Bool {
        scenes.start(scene)
        return scenes.playing.contains(scene)
    }

    func stopScene(_ scene: FormID) {
        scenes.stop(scene)
    }

    func isScenePlaying(_ scene: FormID) -> Bool {
        scenes.playing.contains(scene)
    }
}
