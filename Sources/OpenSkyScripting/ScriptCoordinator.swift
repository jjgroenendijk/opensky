// The session's Papyrus VM, its world bridge, and its state reads.
// Without game data there is no VM, and the readout shows `ScriptsSnapshot.empty`.

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
    /// Nil without game data.
    public let runtime: PapyrusWorldRuntime?
    /// The seam natives reach the world through.
    public let bridge: PapyrusWorldStateBridge?
    /// Scripts with their ancestors, loaded off the main actor once play starts.
    private let scripts: AssetLoader<String, [PexFile]>?
    weak let world: (any ScriptWorld)?
    /// The player's location at the last frame. The outer nil means no frame has read it.
    private var lastPlayerLocation: ResolvedFormID??

    /// Without game data there is no VM, and every call does nothing.
    public convenience init(world: any ScriptWorld) {
        self.init(world: world, runtime: nil, bridge: nil)
    }

    /// Takes a VM built elsewhere, such as a test fixture's.
    public convenience init(
        world: any ScriptWorld, runtime: PapyrusWorldRuntime?, bridge: PapyrusWorldStateBridge?
    ) {
        self.init(world: world, runtime: runtime, bridge: bridge, scripts: nil)
    }

    /// The VM's registry owns the bridge, so the bridge holds the VM weakly.
    private init(
        world: any ScriptWorld,
        runtime: PapyrusWorldRuntime?,
        bridge: PapyrusWorldStateBridge?,
        scripts: AssetLoader<String, [PexFile]>?
    ) {
        self.world = world
        self.runtime = runtime
        self.bridge = bridge
        self.scripts = scripts
        bridge?.world = runtime
    }

    /// Builds the VM over `bridge`, with scripts decoded on demand from `fileSystem`.
    public convenience init(
        world: any ScriptWorld,
        bridge: PapyrusWorldStateBridge,
        fileSystem: any GameFileSource
    ) {
        let runtime = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeRegistry.standard(
                context: PapyrusNativeContext(world: bridge)
            )
        ))
        runtime.runtime.nativeTiming = .game
        // Session start runs before the first frame, so it may load at once.
        runtime.scriptProvider = Self.scriptProvider(fileSystem: fileSystem)
        self.init(
            world: world,
            runtime: runtime,
            bridge: bridge,
            scripts: AssetLoader(load: Self.chainLoad(fileSystem: fileSystem))
        )
    }

    /// Starts the scripts of the quests that already run. Session start calls it once.
    public func startQuestScripts() {
        let started = bridge?.attachRunningQuestScripts() ?? 0
        Self.logger.info("[INFO] quest scripts instantiated: \(started, privacy: .public)")
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
        bridge?.updateSunGaze()
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

extension ScriptCoordinator {
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

    /// Freezes only the VM, not the world, so a mid-event VM can be inspected.
    public func setScriptsPaused(_ paused: Bool) {
        runtime?.isPaused = paused
    }

    /// The runtime clamps `ticks`, so a stray value cannot stall the frame.
    public func stepScripts(ticks: Int) {
        runtime?.burst(ticks: ticks, gameClock: world?.gameClock)
    }
}

nonisolated private final class PexParseCache: Sendable {
    let files = Mutex<[String: PexFile]>([:])
}
