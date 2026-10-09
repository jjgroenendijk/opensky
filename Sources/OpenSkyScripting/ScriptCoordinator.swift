// The session's Papyrus VM, its world bridge, and the World > Scripts panel.
// Without game data there is no VM, and the panel shows `ScriptsSnapshot.empty`.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsPEX
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Synchronization

/// What `ScriptCoordinator` reads from the live session.
@MainActor
public protocol ScriptWorld: AnyObject {
    /// The reference under the crosshair, nil when nothing is targeted.
    var crosshairReference: FormID? { get }
    /// Nil when the reference is not resident.
    func referenceKey(formID: FormID) -> ReferenceKey?
    var gameClock: GameClock? { get }
}

@MainActor
public final class ScriptCoordinator {
    /// Nil until `start`.
    public private(set) var runtime: PapyrusWorldRuntime?
    /// The seam natives reach the world through.
    public private(set) var bridge: PapyrusWorldStateBridge?
    /// Scripts with their ancestors, loaded off the main actor once play starts.
    private var scripts: AssetLoader<String, [PexFile]>?
    weak var world: (any ScriptWorld)?

    public init() {}

    public func attach(world: any ScriptWorld) {
        self.world = world
    }

    /// Builds the VM over `bridge`, with scripts decoded on demand from
    /// `fileSystem`. The VM's registry owns the bridge, so the bridge holds the
    /// VM weakly.
    @discardableResult
    public func start(
        bridge: PapyrusWorldStateBridge, fileSystem: any GameFileSource
    ) -> PapyrusWorldRuntime {
        let runtime = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeRegistry.standard(
                context: PapyrusNativeContext(world: bridge)
            )
        ))
        // Session start runs before the first frame, so it may load at once.
        runtime.scriptProvider = Self.scriptProvider(fileSystem: fileSystem)
        scripts = AssetLoader(load: Self.chainLoad(fileSystem: fileSystem))
        install(runtime: runtime, bridge: bridge)
        return runtime
    }

    /// The frame's drain point. The first call is the first frame: from then on,
    /// scripts load off the main actor, and work that waits for one runs here.
    public func drainLoads() {
        guard let runtime, let scripts else { return }
        scripts.drain()
        if runtime.scriptLibrary == nil {
            runtime.scriptLibrary = { [weak scripts] name in
                guard let scripts else { return .failed(AssetLoadFailure(reason: "no loader")) }
                let key = PapyrusRuntime.key(name)
                let state = scripts.state(of: key)
                switch state {
                case .ready: scripts.evict { $0 == key }
                case let .failed(failure): Self.logUnavailable(name, failure)
                case .loading: break
                }
                return state
            }
        }
        runtime.retryDeferredScriptWork()
    }

    /// Takes a VM built elsewhere, such as a test fixture's.
    public func install(runtime: PapyrusWorldRuntime?, bridge: PapyrusWorldStateBridge?) {
        bridge?.world = runtime
        self.runtime = runtime
        self.bridge = bridge
    }

    /// Gives the bridge its quest layer and starts the quests that already run.
    public func attachQuests(_ quests: any QuestAccess) {
        bridge?.questRuntime = quests
        let started = bridge?.attachRunningQuestScripts() ?? 0
        Self.logger.info("[INFO] quest scripts instantiated: \(started, privacy: .public)")
    }

    /// The renderer gates `delta`, so a menu-paused frame advances nothing.
    public func advance(delta: Float) {
        _ = runtime?.advance(delta: delta, gameClock: world?.gameClock)
    }

    /// Quest instances first, so saved variables have somewhere to go. Timers
    /// last, because each one names an instance that must already exist.
    public func restore(instances: [PapyrusInstanceState], timers: [PapyrusTimerState]) {
        bridge?.attachRunningQuestScripts()
        runtime?.restore(instanceStates: instances)
        runtime?.restore(timerStates: timers)
    }

    /// A script that fails to load is logged once, because `PapyrusWorldRuntime`
    /// remembers the miss. A broken mod script must not stop streaming.
    private static func scriptProvider(
        fileSystem: any GameFileSource
    ) -> (String) -> PexFile? {
        let loader = PexScriptLoader(fileSystem: fileSystem)
        return { name in
            do {
                return try loader.load(name)
            } catch {
                logUnavailable(name, AssetLoadFailure(error))
                return nil
            }
        }
    }

    /// The worker's load: the script, then each ancestor that loads. Parsed files
    /// stay in a worker-side cache, because most scripts share a few ancestors.
    private static func chainLoad(
        fileSystem: any GameFileSource
    ) -> @Sendable (String) throws -> [PexFile] {
        let parsed = PexParseCache()
        let load: @Sendable (String) throws -> PexFile = { name in
            let key = PapyrusRuntime.key(name)
            if let cached = parsed.files.withLock({ $0[key] }) {
                return cached
            }
            let file = try PexScriptLoader.load(name) { try fileSystem.contents(forPath: $0) }
            parsed.files.withLock { $0[key] = file }
            return file
        }
        return { name in
            var chain = try [load(name)]
            var visited: Set<String> = [PapyrusRuntime.key(name)]
            var current = name
            while
                let parent = chain.last?.objects
                    .first(where: { PapyrusRuntime.key($0.name) == PapyrusRuntime.key(current) })?
                    .parentClassName,
                !parent.isEmpty,
                visited.insert(PapyrusRuntime.key(parent)).inserted,
                let file = try? load(parent)
            {
                chain.append(file)
                current = parent
            }
            return chain
        }
    }

    private static func logUnavailable(_ name: String, _ failure: AssetLoadFailure) {
        logger.warning(
            """
            [WARNING] script \(name, privacy: .public) unavailable: \
            \(failure.reason, privacy: .public)
            """
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Papyrus"
    )
}

extension ScriptCoordinator: ScriptControlProviding {
    /// Targets the crosshair. An unresolved FormID still shows as itself, so the
    /// readout never goes blank while the crosshair is on something.
    public var scriptsSnapshot: ScriptsSnapshot {
        guard let runtime else { return .empty }
        let running = bridge?.questRuntime?.runningQuests().count ?? 0
        let failures = bridge?.questAliasFillFailures ?? 0
        guard let formID = world?.crosshairReference else {
            return runtime.scriptsSnapshot(
                runningQuestCount: running, questAliasFillFailures: failures
            )
        }
        guard let key = world?.referenceKey(formID: formID) else {
            return runtime.scriptsSnapshot(
                targetDescription: formID.description,
                runningQuestCount: running,
                questAliasFillFailures: failures
            )
        }
        return runtime.scriptsSnapshot(
            target: key, runningQuestCount: running, questAliasFillFailures: failures
        )
    }

    public var questAliasQuestEditorIDs: [String] {
        guard let quests = bridge?.questRuntime?.quests else { return [] }
        return quests.sortedQuests()
            .filter { !$0.aliases.isEmpty }
            .compactMap(\.editorID)
    }

    /// Lists every authored alias, filled or not: an empty one is the
    /// interesting case, and hiding it would hide an unimplemented fill type.
    public func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        guard
            let quests = bridge?.questRuntime,
            let quest = quests.quests.quest(editorID: editorID)
        else {
            return nil
        }
        let filled = (try? quests.aliasState(of: quest.formID)) ?? .empty
        let state = try? quests.state(of: quest.formID)
        return ScriptQuestAliasInspection(
            editorID: quest.editorID ?? quest.formID.description,
            formIDText: quest.formID.description,
            isRunning: state?.isRunning ?? false,
            rows: quest.aliases.map { alias in
                ScriptQuestAliasRow(
                    aliasID: alias.id,
                    name: alias.name ?? "",
                    fillType: alias.fillType.name,
                    isOptional: alias.flags.contains(.optional),
                    reference: filled.reference(forAlias: alias.id)?.description
                )
            }
        )
    }

    /// Freezes only the VM, not the world, so a mid-event VM can be inspected.
    public func setScriptsPaused(_ paused: Bool) {
        runtime?.isPaused = paused
    }

    /// The runtime clamps `ticks`, so a stray value cannot stall the frame.
    public func stepScripts(ticks: Int) {
        runtime?.burst(ticks: ticks, gameClock: world?.gameClock)
    }

    public func setScriptInstructionBudget(_ instructions: Int) {
        runtime?.budget.instructions = max(1, instructions)
    }
}

/// Lets the app's provider object stand in for its `ScriptCoordinator`.
public protocol ScriptControlForwarding: ScriptControlProviding {
    var scripts: ScriptCoordinator { get }
}

extension ScriptControlForwarding {
    public var scriptsSnapshot: ScriptsSnapshot {
        scripts.scriptsSnapshot
    }

    public var questAliasQuestEditorIDs: [String] {
        scripts.questAliasQuestEditorIDs
    }

    public func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        scripts.questAliasTable(editorID: editorID)
    }

    public func setScriptsPaused(_ paused: Bool) {
        scripts.setScriptsPaused(paused)
    }

    public func stepScripts(ticks: Int) {
        scripts.stepScripts(ticks: ticks)
    }

    public func setScriptInstructionBudget(_ instructions: Int) {
        scripts.setScriptInstructionBudget(instructions)
    }
}

nonisolated private final class PexParseCache: Sendable {
    let files = Mutex<[String: PexFile]>([:])
}
