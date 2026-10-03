// The shell of scene playback: owns the scene catalog, ticks playing scenes,
// and keeps the last steps and lines for the sidebar. The rules live in
// `SceneRuntime`. See docs/engine/coordinators.md and docs/engine/scenes.md.

import OpenSkyDialogueInterface
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

    public var catalog = SceneCatalog.empty {
        didSet { rescan() }
    }

    public private(set) var trace: [SceneEvent] = []
    public private(set) var lines: [SceneLine] = []
    public var lastOutcome: String?
    /// Scenes known to be playing, so a frame with none builds no runtime.
    public private(set) var playing: Set<FormID> = []
    private var ticksSinceScan = 0
    let dialogue: DialogueCoordinator
    weak var world: (any SceneWorld)?

    public init(dialogue: DialogueCoordinator) {
        self.dialogue = dialogue
    }

    public func attach(world: any SceneWorld) {
        self.world = world
    }

    /// Built per call, like the dialogue runtime it wraps.
    public var runtime: SceneRuntime? {
        guard let dialogueRuntime = dialogue.runtime else { return nil }
        return SceneRuntime(
            catalog: catalog,
            dialogue: dialogueRuntime,
            fragments: world?.sceneFragments,
            host: world,
            now: world?.sceneSeconds ?? 0
        )
    }

    public func start(_ id: FormID) {
        guard let runtime else {
            lastOutcome = "no dialogue index loaded"
            return
        }
        do {
            let events = try runtime.start(id)
            record(events)
            lastOutcome = events.isEmpty ? "already playing" : "started"
        } catch {
            lastOutcome = "start refused: \(String(describing: error))"
        }
    }

    public func stop(_ id: FormID) {
        guard let runtime else { return }
        let events = runtime.stop(id)
        record(events)
        lastOutcome = events.isEmpty ? "not playing" : "stopped"
    }

    /// Advances playing scenes. Builds no runtime while none plays.
    public func tick() {
        ticksSinceScan += 1
        if ticksSinceScan >= Self.rescanInterval {
            rescan()
        }
        guard !playing.isEmpty, let runtime else { return }
        record(runtime.tick())
    }

    /// Starts the quest's begin-on-start scenes.
    public func questDidStart(_ quest: FormID) {
        guard let runtime, !catalog.scenes(ofQuest: quest).isEmpty else { return }
        record(runtime.questDidStart(quest))
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
            case let .line(line): lines.append(line)
            default: break
            }
        }
        trace = Array((trace + events).suffix(Self.historyLimit))
        lines = Array(lines.suffix(Self.historyLimit))
    }
}
