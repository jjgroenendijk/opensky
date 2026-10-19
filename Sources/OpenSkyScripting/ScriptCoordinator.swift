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
    /// The location of the player's cell, `.some(nil)` in the wilderness. Nil while the
    /// cell is not resident, so a cell that streams in is not a move.
    var playerLocation: ResolvedFormID?? { get }
}

@MainActor
public final class ScriptCoordinator {
    /// Nil until `start`.
    public private(set) var runtime: PapyrusWorldRuntime?
    /// The seam natives reach the world through.
    public private(set) var bridge: PapyrusWorldStateBridge?
    /// Scripts with their ancestors, loaded off the main actor once play starts.
    private var scripts: AssetLoader<String, [PexFile]>?
    weak let world: (any ScriptWorld)?
    /// The player's location at the last frame. The outer nil means no frame has read it.
    private var lastPlayerLocation: ResolvedFormID??

    public init(world: any ScriptWorld) {
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
        runtime.runtime.nativeTiming = .game
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

    /// The player slept from `start` to `end`, in game days passed; time has already passed.
    public func reportSleep(start: Double, end: Double) {
        bridge?.world?.queueSleepEvents(start: start, end: end)
    }

    /// The renderer gates `delta`, so a menu-paused frame advances nothing.
    public func advance(delta: Float) {
        queueLocationChange()
        bridge?.queueInventoryEvents()
        bridge?.queueMagicEffectEvents()
        bridge?.queueReferenceStateEvents()
        bridge?.queueCombatStateEvents()
        bridge?.queueTrackedStatEvents()
        bridge?.queueLineOfSightEvents()
        bridge?.advanceTranslations(by: delta)
        bridge?.queueTriggerRepeats(after: delta)
        bridge?.advanceDelayedActivations(by: delta)
        _ = runtime?.advance(delta: delta, gameClock: world?.gameClock)
    }

    /// Time a menu pauses the world for. Only `WaitMenuMode` counts it.
    public func advanceMenuTime(delta: Float) {
        runtime?.advanceMenuTime(delta: delta)
    }

    /// Quest instances first, so saved variables have somewhere to go. Timers
    /// last, because each one names an instance that must already exist. The
    /// player's scripts then hear `OnPlayerLoadGame`.
    public func restore(instances: [PapyrusInstanceState], timers: [PapyrusTimerState]) {
        bridge?.attachRunningQuestScripts()
        runtime?.restore(instanceStates: instances)
        runtime?.restore(timerStates: timers)
        runtime?.queuePlayerLoadGame()
        bridge?.skipInventoryJournal()
        bridge?.skipMagicEffectJournal()
        bridge?.skipReferenceStateJournal()
        bridge?.skipTrackedStatJournal()
        bridge?.clearTranslations()
        lastPlayerLocation = nil
    }

    /// The first frame only records the location: the player started there and did not move.
    private func queueLocationChange() {
        guard let runtime, case let .some(location) = world?.playerLocation else { return }
        defer { lastPlayerLocation = .some(location) }
        guard case let .some(previous) = lastPlayerLocation, previous != location else { return }
        runtime.queueLocationChange(actor: .player, from: previous, to: location)
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
        var snapshot = targetedSnapshot
        snapshot.scriptedMoveCount = bridge?.translations.count ?? 0
        return snapshot
    }

    private var targetedSnapshot: ScriptsSnapshot {
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
        let state = bridge.flatMap { ScriptsReadout.scriptStateText($0.scriptedState(of: key)) }
        return runtime.scriptsSnapshot(
            target: key,
            targetDescription: [key.description, state].compactMap(\.self)
                .joined(separator: "  "),
            runningQuestCount: running,
            questAliasFillFailures: failures
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

    public func setScriptGameTiming(_ enabled: Bool) {
        runtime?.runtime.nativeTiming = enabled ? .game : .runToEnd
    }
}

nonisolated private final class PexParseCache: Sendable {
    let files = Mutex<[String: PexFile]>([:])
}
