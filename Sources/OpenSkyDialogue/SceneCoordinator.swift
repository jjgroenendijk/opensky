// The shell of scene playback: owns the scene catalog, ticks playing scenes,
// and keeps the last steps and lines for state reads. The rules live in
// `SceneRuntime`. See docs/engine/coordinators.md and docs/engine/scenes.md.

import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

/// What `SceneCoordinator` reads from the running session.
@MainActor
public protocol SceneWorld: SceneHost {
    /// Nil in a session with no script runtime.
    var sceneFragments: (any SceneFragmentDispatching)? { get }
    /// Game seconds divided by the time scale.
    var sceneSeconds: Double { get }
}

@MainActor
public final class SceneCoordinator {
    /// Steps and lines the readout keeps.
    public static let historyLimit = 40
    /// Ticks between full scans for scenes a save load started.
    static let rescanInterval = 60

    public let catalog: SceneCatalog
    let conditionCache = RevisionCache<UInt64, SceneConditionBase>()
    let playingCache = RevisionCache<ScenePlayingRevision, [CatalogScene]>()

    public private(set) var trace: [SceneEvent] = []
    public private(set) var lines: [SceneLine] = []
    /// The wait before a repeating scene plays again.
    public let repeatPause: ClosedRange<Float>
    /// Scenes known to be playing, so a frame with none builds no runtime.
    public private(set) var playing: Set<FormID> = []
    private var ticksSinceScan = 0
    /// Lines that wait for their voice file, across the per-call runtimes.
    let pendingLines = ScenePendingLines()
    let dialogue: DialogueCoordinator
    let world: any SceneWorld
    private var pendingCommands: [SceneCommand] = []

    public init(
        dialogue: DialogueCoordinator,
        world: any SceneWorld,
        catalog: SceneCatalog = .empty,
        repeatPause: ClosedRange<Float> = 10 ... 30
    ) {
        self.dialogue = dialogue
        self.world = world
        self.catalog = catalog
        self.repeatPause = repeatPause
        rescan()
    }

    /// Lines said since the last call, also by `start` and `questDidStart`.
    public func takeCommands() -> [SceneCommand] {
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// Built per call, like the dialogue runtime it wraps.
    public var runtime: SceneRuntime? {
        guard let dialogueRuntime = dialogue.runtime else { return nil }
        var runtime = SceneRuntime(
            catalog: catalog,
            dialogue: dialogueRuntime,
            fragments: world.sceneFragments,
            host: world,
            pendingLines: pendingLines,
            playingCache: playingCache,
            now: world.sceneSeconds
        )
        runtime.repeatPause = repeatPause
        return runtime
    }

    /// `force` stops the scenes that share an actor first, as `ForceStart()` does.
    public func start(_ id: FormID, force: Bool = false) {
        guard let runtime else {
            Self.logger.info("scene start: no dialogue index loaded")
            return
        }
        do {
            let events = try force ? runtime.forceStart(id) : runtime.start(id)
            record(events)
            let state = events.isEmpty ? "already playing" : "started"
            Self.logger.info("scene \(id, privacy: .public) \(state, privacy: .public)")
        } catch {
            Self.logger.info("scene start refused: \(String(describing: error), privacy: .public)")
        }
    }

    public func stop(_ id: FormID) {
        guard let runtime else { return }
        let events = runtime.stop(id)
        record(events)
    }

    /// Advances playing scenes. Builds no runtime while none plays.
    /// - Returns: the lines said since the last call.
    public func tick() -> [SceneCommand] {
        ticksSinceScan += 1
        if ticksSinceScan >= Self.rescanInterval {
            rescan()
        }
        if !playing.isEmpty, let runtime {
            record(runtime.tick(scenes: playing))
        }
        return takeCommands()
    }

    /// Starts the quest's begin-on-start scenes.
    public func questDidStart(_ quest: FormID) {
        guard !catalog.scenes(ofQuest: quest).isEmpty, let runtime else { return }
        record(runtime.questDidStart(quest))
    }

    /// Every actor a playing scene holds. Empty while no scene plays.
    public func actorsInScenes() -> Set<ReferenceKey> {
        guard !playing.isEmpty, let runtime else { return [] }
        return runtime.actorsInPlayingScenes()
    }

    /// The playing scene `reference` acts in, or nil.
    public func scene(holding reference: ReferenceKey) -> FormID? {
        guard !playing.isEmpty else { return nil }
        return runtime?.scene(holding: reference)
    }

    /// Finds playing scenes from the store, after a load or a reset.
    public func rescan() {
        ticksSinceScan = 0
        playing = Set(catalog.all.lazy
            .filter { self.dialogue.store.component(SceneRuntimeState.self, for: $0.key) != nil }
            .map(\.formID))
    }

    func record(_ events: [SceneEvent]) {
        guard !events.isEmpty else { return }
        for event in events {
            switch event.step {
            case .began: playing.insert(event.scene)
            case .ended: playing.remove(event.scene)
            case let .line(line):
                lines.append(line)
                pendingCommands.append(.speak(line))
            default: break
            }
        }
        trace = Array((trace + events).suffix(Self.historyLimit))
        lines = Array(lines.suffix(Self.historyLimit))
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Scenes"
    )
}
