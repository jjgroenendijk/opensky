// Papyrus wiring satellite for GameViewController (issue #171): builds the
// session's `PapyrusWorldRuntime`, gives it a lazy script library over the
// install's VFS, binds script instance lifetime to cell streaming, and ticks
// it from the renderer's world-simulation hook.
//
// Split from GameViewControllerStreaming.swift, which is already at its
// split-for-size shape; the wiring here is independent of scene composition.

import OSLog

extension GameViewController {
    /// Creates the VM for this session and subscribes it to the engine.
    ///
    /// Three seams, all one-directional so the engine never depends on the VM:
    /// the streamer announces cell attach and detach, the renderer announces a
    /// world-simulation delta, and the provider supplies compiled scripts. A
    /// provider that cannot supply scripts (a synthetic scene, or an install
    /// whose archives carry no `scripts\` entries) leaves `papyrus` nil rather
    /// than running a VM with an empty library.
    func wirePapyrus(
        provider: any CellSceneProvider,
        renderer: Renderer,
        streamer controller: CellStreamer
    ) {
        guard
            let scriptSource = provider as? ScriptDataProviding,
            let fileSystem = scriptSource.scriptFileSystem
        else { return }
        let bridge = PapyrusWorldStateBridge(
            worldState: worldState, references: controller, globals: globalStore
        )
        bridge.clockSource = { [weak renderer] in renderer?.gameClock }
        // The `Actor` natives' collaborators (issue #375). Closures rather than
        // references, so this wiring step does not have to run after the ones
        // that build them: `wireActorValues` needs a provider and `wireRagdoll`
        // needs a renderer, and neither is ordered against this file.
        bridge.actorValueRuntime = { [weak self] in self?.actorValues.runtime }
        bridge.ragdollRuntime = { [weak self] in self?.ragdoll.runtime }
        // Only the player carries a behavior graph that tracks a draw state, so
        // every other actor answers nil and `IsWeaponDrawn` fails with a reason
        // rather than claiming sheathed.
        bridge.weaponDrawState = { [weak self] key in
            guard key == .player else { return nil }
            return self?.melee.runtime?.state.drawState
        }
        let resolver = scriptSource.scriptFormIDResolver
        bridge.formIDResolver = resolver
        let world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeRegistry.standard(
                context: PapyrusNativeContext(world: PapyrusWorldAccess(bridge: bridge))
            )
        ))
        // Closes the cycle the other way round: the registry inside `world`
        // owns the bridge, so the bridge holds the runtime weakly.
        bridge.world = world
        papyrusBridge = bridge
        controller.onInteraction.add { [weak bridge] event in
            bridge?.handleInteraction(event)
        }
        // Trigger-volume occupancy edges (issue #173). The streamer tests once
        // per rendered frame in walk mode; each edge queues one event per
        // script on the volume's authoring reference.
        controller.onTriggerTransition.add { [weak bridge] event in
            bridge?.handleTriggerTransition(event)
        }
        world.scriptProvider = Self.scriptProvider(fileSystem: fileSystem)
        wireQuests(provider: provider, bridge: bridge)
        controller.onCellAttached = { [weak world] scene, firstIntegration in
            guard let world, let location = scene.location else { return }
            world.attach(
                cell: location,
                references: scene.references,
                formIDResolver: resolver,
                firstIntegration: firstIntegration
            )
        }
        controller.onCellDetached = { [weak world] location in
            world?.detach(cell: location)
        }
        // The renderer gates this delta through its own FrameSimClock, so a
        // menu-paused frame delivers zero and the VM advances nothing.
        renderer.onWorldUpdate = { [weak world, weak renderer] delta in
            guard let world else { return }
            _ = world.advance(delta: delta, gameClock: renderer?.gameClock)
        }
        papyrus = world
    }

    /// Gives the session its quest layer and starts the quests that are
    /// already running (issue #322).
    ///
    /// Which quests those are is the #182 state's answer, not this file's: at
    /// wire-up it is every quest whose DNAM says start-game-enabled, and after
    /// a save is restored it is whatever that save recorded. Their scripts are
    /// instantiated once here; `Start` and `Stop` maintain the set afterwards.
    ///
    /// A provider with no QUST index leaves `questRuntime` nil, and every
    /// `Quest` native then fails with `PapyrusQuestBridgeError.noQuestData`.
    private func wireQuests(
        provider: any CellSceneProvider,
        bridge: PapyrusWorldStateBridge
    ) {
        guard let store = (provider as? QuestDataProviding)?.questStore else {
            return
        }
        questStore = store
        bridge.questRuntime = QuestRuntime(store: worldState, quests: store)
        let started = bridge.attachRunningQuestScripts()
        Self.papyrusLogger.info(
            "[INFO] quest scripts instantiated: \(started, privacy: .public)"
        )
    }

    /// Decodes one `.pex` on demand. A script that fails to load is logged
    /// once — `PapyrusWorldRuntime` remembers the miss and never asks again —
    /// and counted as a skipped attach, because a mod-authored or truncated
    /// script must not stop the world from streaming.
    private static func scriptProvider(
        fileSystem: VirtualFileSystem
    ) -> (String) -> PexFile? {
        let loader = PexScriptLoader(fileSystem: fileSystem)
        return { name in
            do {
                return try loader.load(name)
            } catch {
                papyrusLogger.warning(
                    """
                    [WARNING] script \(name, privacy: .public) unavailable: \
                    \(String(describing: error), privacy: .public)
                    """
                )
                return nil
            }
        }
    }

    private static let papyrusLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Papyrus"
    )
}
