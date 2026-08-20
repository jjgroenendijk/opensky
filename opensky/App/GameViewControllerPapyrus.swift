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
        // The combat loop, which `StartCombat`, `StopCombat` and `IsInCombat`
        // reach through (issue #424).
        bridge.combatRuntime = { [weak self] in self?.combat.runtime }
        wireSpellNatives(bridge: bridge, provider: provider)
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
        let locations = (provider as? LocationDataProviding)?.locationStore
        bridge.questRuntime = QuestRuntime(
            store: worldState,
            quests: store,
            locations: locations
        )
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

extension GameViewController {
    /// The spell natives' collaborators (issue #474, roadmap item 19.11).
    ///
    /// Closures for the reason the actor ones are: `wireCasting` and
    /// `wireMagicEffects` both run after this step, and a reference captured
    /// here would be nil forever. The dispel closure carries the whole
    /// read-modify-write because `ActiveEffectRuntime` is a struct this
    /// controller owns by value — handing out a copy would drop the write.
    func wireSpellNatives(
        bridge: PapyrusWorldStateBridge,
        provider: any CellSceneProvider
    ) {
        bridge.casterRuntime = { [weak self] in self?.casting.runtime }
        bridge.magicEffectStore = (provider as? MagicDataProviding)?.magicEffectStore
        bridge.dispelEffects = { [weak self] holder, predicate in
            guard let self, var runtime = magicEffects.runtime else { return 0 }
            let removed = runtime.dispel(on: holder, where: predicate)
            magicEffects.runtime = runtime
            return removed
        }
        bridge.applySpellHit = { [weak self] hit in
            self?.applySpellHit(hit) ?? .none
        }
        wirePerkNatives(bridge: bridge)
    }

    /// The perk natives' collaborators (issue #497, roadmap item 20.4).
    ///
    /// Closures for the reason the spell ones are: `wirePerks` runs after this
    /// step, and the mutation closure carries the whole write because
    /// `PerkRuntime` is a struct this controller owns by value — and because
    /// granting a perk has to reconcile the abilities it grants in the same
    /// call, which is a step the bridge should not know about.
    private func wirePerkNatives(bridge: PapyrusWorldStateBridge) {
        bridge.mutatePerks = { [weak self] mutation, perk, actor in
            guard let self, let holder = actorValueHolder(for: actor) else { return false }
            return switch mutation {
            case .add: addPerk(perk, to: holder)
            case .remove: removePerk(perk, from: holder)
            }
        }
        bridge.perkOwnership = { [weak self] key in
            self?.perkOwnership(of: key)
        }
        // `wireSkills` runs after this step too, and the closure carries the
        // whole write because `SkillAdvancementRuntime` is a struct this
        // controller owns by value (issue #498).
        bridge.advanceSkill = { [weak self] advance, index, magnitude in
            self?.advancePlayerSkill(advance, at: index, by: magnitude) ?? false
        }
        // `wireProgression` runs after this step as well (issue #499). A zero
        // delta is the read `Game.GetPerkPoints` makes, which is why one
        // closure answers both natives.
        bridge.modifyPerkPoints = { [weak self] delta in
            self?.modifyPlayerPerkPoints(by: delta)
        }
    }
}
