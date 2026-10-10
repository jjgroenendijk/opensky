// App side of scenes and the story manager: builds the scene catalog, runs the
// session-start pass, starts quests with their scripts, ticks scenes, and turns
// deaths and location changes into story events. The rules live in the
// coordinators (docs/engine/scenes.md, docs/engine/story-manager.md).

import Foundation
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyProgression
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
    private var sessionStartLists: [PluginQuestList] = []
    /// Nil until the first check; then the player's last known location, or none.
    private var lastPlayerLocation: ResolvedFormID??
    private var framesSinceLocationCheck = 0
    /// Frames between location checks, because each builds a condition context.
    static let locationCheckInterval = 30
    /// Voice file lengths for scene lines. Nil without game data.
    private var voiceTimer: SceneVoiceTimer?
    /// Voice file paths for scene and menu lines. Nil without game data.
    private var voiceLocator: VoiceLineLocator?

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
        // The quest store's space, so a DLC scene names its quest as the runtime does.
        let questStore = (provider as? QuestDataProviding)?.questStore
        if let store = data.scenes, let quests = questStore {
            scenes.catalog = SceneCatalog(store: store, resolver: quests.resolver)
        }
        if
            let dialogue = (provider as? DialogueDataProviding)?.dialogueStore,
            let files = game.audioFileSystem
        {
            let locator = VoiceLineLocator(dialogue: dialogue, quests: questStore)
            voiceLocator = locator
            voiceTimer = SceneVoiceTimer(
                locator: locator, read: { try files.contents(forPath: $0) }
            )
        }
        storyManager.story = data.storyManager
        game.progression.storyEvents = self
        game.inventory.storyEvents = self
        game.crime.storyEvents = self
        game.magic.storyEvents = self
        game.scripts.bridge?.story = self
        game.scripts.bridge?.menus = game.menuWorld
        game.scripts.bridge?.trapWorld = game.effectsWorld
        game.scripts.bridge?.logEntryEvaluator = { [weak self] in
            ConditionEvaluator(
                context: self?.conditionContext() ?? ConditionContext(), registry: .standard
            )
        }
        if let files = scripts?.scriptFileSystem {
            sessionStartLists = data.plugins.map {
                PluginQuestList.load(plugin: $0.name, masters: $0.masters, files: files)
            }
            runSessionStart(lists: sessionStartLists)
        }
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advancePreviousSystems?(delta)
            self?.voiceTimer?.drain()
            self?.scenes.tick()
            self?.checkPlayerLocation()
        }
    }

    /// A new game starts the same listed quests again over the cleared state.
    func rerunSessionStart() {
        runSessionStart(lists: sessionStartLists)
    }

    /// Its start-up stage moves the player to the opening, so it runs last.
    func startOpeningQuest() {
        guard let quest = questRuntime?.quests.formID(editorID: NewGameStart.openingQuest) else {
            game.hud.showNotification("New game: no \(NewGameStart.openingQuest) quest")
            return
        }
        do {
            try startQuest(quest, event: nil)
        } catch {
            game.hud.showNotification("New game: \(NewGameStart.openingQuest) did not start")
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

    /// `KILL`. The murder is settled first, so the crime status can say whether
    /// it was reported. The rank is unchanged by the death.
    func reportKill(victim: ReferenceKey, killer: ReferenceKey?) {
        game.crime.reportMurder(of: victim)
        var rank: Int8 = 0
        if
            let killer, let known = game.scripts.bridge?.relationshipRank(
                of: victim,
                toward: killer
            )
        {
            rank = known ?? 0
        }
        storyManager.fire(.kill(
            killer: killer,
            victim: victim,
            location: game.runtimeState.conditionContext().data.currentLocation(of: victim),
            status: game.crime.killStatus(of: victim, by: killer),
            rankBeforeDeath: rank
        ))
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

extension StoryWorldAdapter: StoryEventReporting {
    /// An event with no `L1` takes the location of its `R1`, or the player's.
    func reportStoryEvent(_ event: StoryEventData) {
        var event = event
        if event.location1 == nil {
            event.location1 = game.runtimeState.conditionContext().data
                .currentLocation(of: event.actor1 ?? .player)
        }
        storyManager.fire(event)
    }
}

extension StoryWorldAdapter: StoryManagerWorld {
    /// With the dialogue facts, because event nodes such as `ADIA` test voice types.
    func conditionContext() -> ConditionContext {
        game.dialogueWorld.conditionContext()
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

    func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float? {
        let texts = responseTexts(of: info)
        guard let voiceTimer else { return SceneCore.lineDuration(texts: texts) }
        return voiceTimer.duration(of: info, voiceType: voiceTypeName(of: speaker), texts: texts)
    }

    /// A shared INFO (`DNAM`) says its target's text.
    private func responseTexts(of info: TopicInfo) -> [String?] {
        let info = game.dialogue.index?.responseSource(ofInfo: info.formID) ?? info
        let strings = game.dialogue.strings
        return info.responses.map { response in
            strings.flatMap { response.resolvedText(using: $0) }
        }
    }

    /// The `VTCK` editor ID, which names the voice folder.
    private func voiceTypeName(of speaker: ReferenceKey) -> String? {
        guard
            let voice = game.dialogueWorld.residentVoiceTypes()[speaker],
            let record = game.dialogue.index?.voiceType(voice)
        else { return nil }
        return record.editorID
    }

    /// The voice files `speaker` says `info` with, in response order. Empty
    /// without game data or a known voice type.
    func voicePaths(of info: FormID, speaker: ReferenceKey) -> [String] {
        guard
            let voiceLocator,
            let record = voiceLocator.dialogue.info(info),
            let voiceType = voiceTypeName(of: speaker)
        else { return [] }
        return voiceLocator.lines(info: record, voiceType: voiceType).map(\.path)
    }

    func sceneLineSpoken(_ line: SceneLine) {
        game.audio.speak(voicePaths(of: line.info, speaker: line.speaker), speaker: line.speaker)
        let text = game.dialogue.runtime?.dialogue.info(line.info)
            .map { responseTexts(of: $0).compactMap(\.self).joined(separator: " ") } ?? ""
        game.subtitles.say(
            text, kind: .general, seconds: Double(line.seconds),
            now: Date().timeIntervalSinceReferenceDate
        )
    }

    func runScenePackages(
        _ packages: [FormID], actor: ReferenceKey, owner: ScenePackageOwner
    ) -> ScenePackageState {
        let override = PackageOverride(
            packages: packages,
            owner: PackageOverrideOwner(source: owner.scene, slot: owner.action),
            aliasQuest: scenes.catalog.scene(owner.scene)?.quest
        )
        return game.packages.runOverride(override, actor: actor) == .done ? .done : .running
    }

    func releaseScenePackages(actor: ReferenceKey, owner: ScenePackageOwner) {
        game.packages.clearOverride(
            owner: PackageOverrideOwner(source: owner.scene, slot: owner.action), actor: actor
        )
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
