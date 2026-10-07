// Scene playback over `WorldStateStore`: start, stop, and advance phases. A phase
// starts when its start conditions pass and ends when the actions that end in it
// are done or its completion conditions pass (<https://ck.uesp.net/wiki/Category:Scenes>).
// Rules and what is not done: docs/engine/scenes.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyWorldState

/// What the scene runtime asks of the running session.
@MainActor
public protocol SceneHost: AnyObject {
    /// Seconds a selected line takes to say, or nil while its voice file loads.
    func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float?
    /// Stops the quest, for a scene flagged to stop its quest on end.
    func stopQuest(_ quest: FormID)
    /// Gives `actor` the action's packages ahead of its schedule, or keeps them.
    /// Called again each tick while the action runs, so a loaded save picks them up.
    func runScenePackages(
        _ packages: [FormID], actor: ReferenceKey, owner: ScenePackageOwner
    ) -> ScenePackageState
    /// Hands `actor` back to its schedule, when `owner` still holds it.
    func releaseScenePackages(actor: ReferenceKey, owner: ScenePackageOwner)
}

/// The scene action that holds an actor's packages.
nonisolated public struct ScenePackageOwner: Hashable, Sendable {
    public let scene: FormID
    public let action: UInt32

    public init(scene: FormID, action: UInt32) {
        self.scene = scene
        self.action = action
    }
}

nonisolated public enum ScenePackageState: Equatable, Sendable {
    case running
    /// The package reached its Done state, which completes the action.
    case done
}

/// Lines whose voice file still loads. Kept outside the saved scene state: a save
/// loaded during the wait ends the line at once.
@MainActor
public final class ScenePendingLines {
    var lines: [ScenePackageOwner: SceneLine] = [:]

    public init() {}

    public var isEmpty: Bool {
        lines.isEmpty
    }
}

@MainActor
public struct SceneRuntime {
    public let catalog: SceneCatalog
    /// Selection, said-state, and result scripts of dialogue actions.
    public let dialogue: DialogueRuntime
    public var fragments: (any SceneFragmentDispatching)?
    public weak var host: (any SceneHost)?
    public let pendingLines: ScenePendingLines
    /// Scene seconds: game seconds divided by the time scale.
    public var now: Double

    public init(
        catalog: SceneCatalog,
        dialogue: DialogueRuntime,
        fragments: (any SceneFragmentDispatching)? = nil,
        host: (any SceneHost)? = nil,
        pendingLines: ScenePendingLines = ScenePendingLines(),
        now: Double = 0
    ) {
        self.catalog = catalog
        self.dialogue = dialogue
        self.fragments = fragments
        self.host = host
        self.pendingLines = pendingLines
        self.now = now
    }

    var store: WorldStateStore {
        dialogue.store
    }

    public func state(of id: FormID) -> SceneRuntimeState? {
        catalog.scene(id).flatMap { store.component(SceneRuntimeState.self, for: $0.key) }
    }

    public func isPlaying(_ id: FormID) -> Bool {
        state(of: id) != nil
    }

    /// Playing scenes in FormID order.
    public func playingScenes() -> [CatalogScene] {
        catalog.all.filter { store.component(SceneRuntimeState.self, for: $0.key) != nil }
    }

    /// Starts the scene: the begin fragment, then phase 1. A playing scene is left as it is.
    @discardableResult
    public func start(_ id: FormID) throws -> [SceneEvent] {
        guard let entry = catalog.scene(id) else { throw SceneError.unknownScene(id) }
        guard dialogue.isRunning(quest: entry.quest) else {
            throw SceneError.questNotRunning(entry.quest ?? FormID(0))
        }
        guard store.component(SceneRuntimeState.self, for: entry.key) == nil else { return [] }
        var playback = Playback(
            runtime: self, entry: entry, state: SceneRuntimeState(), isNew: true
        )
        playback.note(.began)
        playback.runFragment(slot: 0x01)
        playback.advance()
        return playback.finish()
    }

    /// Stops a playing scene. Its end fragment runs, as it does however a scene ends.
    @discardableResult
    public func stop(_ id: FormID, reason: SceneEndReason = .stopped) -> [SceneEvent] {
        guard
            let entry = catalog.scene(id),
            let state = store.component(SceneRuntimeState.self, for: entry.key)
        else {
            return []
        }
        var playback = Playback(runtime: self, entry: entry, state: state, isNew: false)
        playback.end(reason)
        return playback.finish()
    }

    /// Advances every playing scene: stops those whose quest stopped, completes
    /// timed actions, and moves phases on.
    public func tick() -> [SceneEvent] {
        var events: [SceneEvent] = []
        for entry in playingScenes() {
            guard let state = store.component(SceneRuntimeState.self, for: entry.key)
            else { continue }
            var playback = Playback(runtime: self, entry: entry, state: state, isNew: false)
            if dialogue.isRunning(quest: entry.quest) {
                playback.advance()
            } else {
                playback.end(.questStopped)
            }
            events += playback.finish()
        }
        return events
    }

    /// Starts the scenes of `quest` flagged to begin on quest start.
    public func questDidStart(_ quest: FormID) -> [SceneEvent] {
        catalog.scenes(ofQuest: quest)
            .filter { $0.scene.flags.contains(.beginOnQuestStart) }
            .flatMap { (try? start($0.formID)) ?? [] }
    }
}
