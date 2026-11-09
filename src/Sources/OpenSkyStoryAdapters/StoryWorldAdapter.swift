// App side of scenes and the story manager: builds the scene catalog, runs the
// session-start pass, starts quests with their scripts, ticks scenes, and turns
// deaths and location changes into story events. The rules live in the
// coordinators (docs/engine/scenes.md, docs/engine/story-manager.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
public import OpenSkyConditions
import OpenSkyCrime
public import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyMenusInterface
public import OpenSkyQuests
public import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `StoryWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol StoryWorldHost: AnyObject {
    var audioFileSystem: (any GameFileSource)? { get }
    var scenes: any ScenePort { get }
    var storyManager: any StoryManagerPort { get }
    var crime: any CrimePort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var followerCommandWorld: any FollowerCommandWorldPort { get }
    var hud: any HUDPort { get }
    var mapWorld: any MapWorldPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var scripts: any ScriptPort { get }
}

public final class StoryWorldAdapter {
    public let game: any StoryWorldHost
    public let state = StoryPartState()
    /// Quests the session-start pass started, whose stages wait for one script attach.
    private var deferredStarts: [FormID]?
    var sessionStartLists: [PluginQuestList] = []
    /// Nil until the first check; then the player's last known location, or none.
    private var lastPlayerLocation: ResolvedFormID??
    private var framesSinceLocationCheck = 0
    /// Frames between location checks, because each builds a condition context.
    public static let locationCheckInterval = 30

    public var scenes: any ScenePort {
        game.scenes
    }

    public var storyManager: any StoryManagerPort {
        game.storyManager
    }

    public let ambientTalkHost: any StoryAmbientTalkHost
    public let socialSearchHost: any StorySocialSearchHost
    public let sceneLinesHost: any StorySceneLinesHost
    public let sceneCastHost: any StorySceneCastHost

    public var ambientTalk: StoryAmbientTalkAdapter {
        StoryAmbientTalkAdapter(
            game: ambientTalkHost, state: state, sceneCast: sceneCast, sceneLines: sceneLines
        )
    }

    public var socialSearch: StorySocialSearchAdapter {
        StorySocialSearchAdapter(game: socialSearchHost, sceneCast: sceneCast)
    }

    public var sceneLines: StorySceneLinesAdapter {
        StorySceneLinesAdapter(game: sceneLinesHost, state: state, sceneCast: sceneCast)
    }

    public var sceneCast: StorySceneCastAdapter {
        StorySceneCastAdapter(game: sceneCastHost)
    }

    public init(game: some StoryWorldHost & StoryAmbientTalkHost & StorySocialSearchHost &
        StorySceneLinesHost & StorySceneCastHost)
    {
        ambientTalkHost = game
        socialSearchHost = game
        sceneLinesHost = game
        sceneCastHost = game
        self.game = game
    }

    /// A new game starts the same listed quests again over the cleared state.
    public func rerunSessionStart() {
        storyManager.social.reset()
        runSessionStart(lists: sessionStartLists)
    }

    /// Its start-up stage moves the player to the opening, so it runs last.
    /// False when the quest is missing or did not start.
    @discardableResult
    public func startOpeningQuest() -> Bool {
        guard let quest = questRuntime?.quests.formID(editorID: NewGameStart.openingQuest) else {
            game.hud.showNotification("New game: no \(NewGameStart.openingQuest) quest")
            return false
        }
        do {
            try startQuest(quest, event: nil)
            return true
        } catch {
            game.hud.showNotification("New game: \(NewGameStart.openingQuest) did not start")
            return false
        }
    }

    /// Starts every listed quest, then attaches scripts once and runs the start-up stages.
    public func runSessionStart(lists: [PluginQuestList]) {
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
    public func reportKill(victim: ReferenceKey, killer: ReferenceKey?) {
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
    func checkPlayerLocation() {
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

    public var questRuntime: QuestRuntime? {
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
            _ = attempt { try game.scripts.bridge?.setQuestStage(stage.index, for: key) }
        }
        scenes.questDidStart(quest)
    }
}

extension StoryWorldAdapter {
    /// The HUD names a quest a Fail Quest stage item failed. The game's own quest
    /// update banner is not built, so this is a notification.
    public func questFailed(_ quest: FormID) {
        guard let record = questRuntime?.quests.quest(quest) else { return }
        let name = game.mapWorld.text(record.name) ?? record.editorID ?? "Quest"
        game.hud.showNotification("\(name) failed")
    }
}

extension StoryWorldAdapter: QuestStarting {
    public func startQuest(_ quest: FormID, event: StoryEventData?) throws {
        guard let runtime = questRuntime else { throw QuestError.unknownQuest(quest) }
        try runtime.startQuest(quest, event: event)
        if deferredStarts != nil {
            deferredStarts?.append(quest)
            return
        }
        game.scripts.bridge?.attachScripts(ofQuest: quest)
        if let event {
            game.scripts.bridge?.queueStoryStartEvent(quest: quest, event: event)
        }
        finishStart(quest)
    }
}

extension StoryWorldAdapter: StoryEventReporting {
    /// An event with no `L1` takes the location of its `R1`, or the player's.
    public func reportStoryEvent(_ event: StoryEventData) {
        storyManager.fireLocated(event) { [game] in game.runtimeState.conditionContext() }
    }
}

extension StoryWorldAdapter: StoryManagerWorld {
    /// With the dialogue facts, because event nodes such as `ADIA` test voice types.
    public func conditionContext() -> ConditionContext {
        game.dialogueWorld.conditionContext()
    }

    public var conditionRegistry: ConditionFunctionRegistry {
        .standard
    }

    public var questStarter: (any QuestStarting)? {
        self
    }
}

extension StoryWorldAdapter: SceneWorld {}

extension StoryWorldAdapter: PapyrusStoryBridge {
    public func sendStoryEvent(_ event: StoryEventData) -> Bool {
        !(storyManager.fire(event)?.startedQuests.isEmpty ?? true)
    }

    public func startScene(_ scene: FormID, force: Bool) -> Bool {
        scenes.start(scene, force: force)
        return scenes.playing.contains(scene)
    }

    public func stopScene(_ scene: FormID) {
        scenes.stop(scene)
    }

    public func isScenePlaying(_ scene: FormID) -> Bool {
        scenes.playing.contains(scene)
    }

    public func currentScene(of reference: ReferenceKey) -> FormID? {
        scenes.scene(holding: reference)
    }
}

extension StoryWorldAdapter: StoryWorldPort {}
