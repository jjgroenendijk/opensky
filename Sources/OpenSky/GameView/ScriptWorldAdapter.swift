// App side of `ScriptCoordinator`: builds the world bridge, gives its natives
// their collaborators, binds script lifetime to cell streaming, and ticks the
// VM from the renderer. The readout logic lives in the coordinator.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol ScriptWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var aiWorld: AIWorldAdapter { get }
    var audio: AudioCoordinator { get }
    var combat: CombatCoordinator { get }
    var containerMenu: ContainerMenuController { get }
    var crime: CrimeCoordinator { get }
    var effectsWorld: EffectsWorldAdapter { get }
    var factionWorld: FactionWorldAdapter { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var magic: MagicCoordinator { get }
    var magicWorld: MagicWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var messages: MessageCoordinator { get }
    var objectAnimationWorld: ObjectAnimationWorldAdapter { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var packages: PackageCoordinator { get }
    var perception: PerceptionCoordinator { get }
    var perks: PerkCoordinator { get }
    var player: PlayerCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var ragdoll: RagdollCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var combatWorld: CombatWorldAdapter { get }
    var effects: EffectsCoordinator { get }
    var menuWorld: MenuWorldAdapter { get }
    var saveGames: SaveGameWorldAdapter { get }
    func quitToMainMenu()
    func quitApplication()
    var runtimeState: RuntimeStateCoordinator { get }
    var runtimeStateWorld: RuntimeStateWorldAdapter { get }
    var scripts: ScriptCoordinator { get set }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var mountWorld: MountWorldAdapter { get }
    var worldState: WorldStateStore { get }
}

final class ScriptWorldAdapter {
    unowned let game: any ScriptWorldHost
    /// Each model's node origins in model space, keyed by lowercased node name.
    var modelNodes: AssetLoader<String, [String: SIMD3<Float>]>?
    /// Node lookups that wait for their model to load.
    var nodeWaits: [ModelNodeWait] = []
    var nextNodeToken = ModelNodeWait.firstToken

    init(game: any ScriptWorldHost) {
        self.game = game
    }

    /// Builds the bridge with every seam, then the VM over it. The streamer, the
    /// renderer, and the provider each feed the VM one way, so the engine never
    /// depends on it. Without compiled scripts there is no VM.
    func wirePapyrus(
        provider: WorldDataStores,
        gameSession: GameSession,
        streamer: CellStreamer
    ) {
        guard
            let fileSystem = provider.scriptFileSystem
        else { return }
        let bridge = PapyrusWorldStateBridge(
            worldState: game.worldState, references: streamer,
            globals: game.runtimeState.globalStore,
            seams: seams(provider: provider)
        )
        bridge.sessionNatives.clockSource = { [weak gameSession] in gameSession?.gameClock }
        wireActorNatives(bridge: bridge)
        wireLineOfSight(bridge: bridge)
        wireSpellNatives(bridge: bridge, provider: provider)
        wireSky(bridge: bridge)
        wireModelNodes(provider: provider, gameSession: gameSession)
        wireGameNatives(bridge: bridge, provider: provider)
        bridge.sessionNatives.itemScripts = Self.itemScripts(provider.placedRecords)
        let resolver = provider.scriptFormIDResolver
        bridge.formIDResolver = resolver
        bridge.playerNatives
            .playersLastMount = { [weak game] in game?.vehicleWorld.vehicles.playersLastMount }
        bridge.playerNatives.dismount = { [weak game] actor in
            game?.mountWorld.dismount(actor) ?? false
        }
        bridge.playerNatives
            .togglePlayerSneaking = { [weak game] in game?.player.isSneaking.toggle() }
        bridge.playerNatives
            .toggleMenus = { [weak game] in game?.hud.update { $0.layerEnabled.toggle() } }
        let scripts = ScriptCoordinator(world: self, bridge: bridge, fileSystem: fileSystem)
        game.scripts = scripts
        let world = scripts.runtime
        streamer.onInteraction.add { [weak bridge] event in
            bridge?.handleInteraction(event)
        }
        // The streamer tests trigger volumes once per walk-mode frame; each edge
        // queues one event per script on the volume's reference.
        streamer.onTriggerTransition.add { [weak bridge] event in
            bridge?.handleTriggerTransition(event)
        }
        scripts.startQuestScripts()
        streamer.onCellAttached = { [weak world] scene, firstIntegration in
            guard let world, let location = scene.location else { return }
            world.attach(
                cell: location,
                references: scene.references,
                formIDResolver: resolver,
                firstIntegration: firstIntegration
            )
        }
        streamer.onCellDetached = { [weak world] location in
            world?.detach(cell: location)
        }
        gameSession.worldTick.register(.scripts) { [weak self, weak gameSession] delta in
            self?.game.scripts.advance(delta: delta)
            let menuTime = gameSession?.consumeMenuTime() ?? 0
            if menuTime > 0 {
                self?.game.scripts.advanceMenuTime(delta: menuTime)
            }
        }
    }

    /// The features the natives reach, each answered by its world adapter.
    private func seams(provider: WorldDataStores) -> PapyrusBridgeSeams {
        var seams = PapyrusBridgeSeams()
        seams.quests = quests(provider: provider)
        seams.inventory = game.inventoryWorld
        seams.alchemy = game.inventoryWorld
        seams.actorAI = game.vehicleWorld
        seams.furniture = game.aiWorld
        seams.objectAnimation = game.audioFileSystem == nil ? nil : game.objectAnimationWorld
        seams.story = game.storyWorld
        seams.menus = game.menuWorld
        seams.trapWorld = game.effectsWorld
        seams.presenter = game.messages
        seams.itemNotices = ItemNoticeTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        seams.effectPresenter = game.effectsWorld
        seams.weather = self
        seams.music = self
        return seams
    }

    /// Without a QUST index every `Quest` native fails with
    /// `PapyrusQuestBridgeError.noQuestData`.
    private func quests(provider: WorldDataStores) -> QuestRuntime? {
        guard let store = provider.questStore else { return nil }
        var runtime = QuestRuntime(
            store: game.worldState,
            quests: store,
            locations: provider.locationStore
        )
        runtime.referenceSearch = { [weak game] in game?.storyWorld.questReferenceSearch() }
        runtime.referenceCreator = { [weak game] base, anchor in
            game?.storyWorld.createQuestReference(base, at: anchor)
        }
        return runtime
    }

    /// Getters, not captured values: the runtimes behind them are wired after
    /// this step.
    private func wireActorNatives(bridge: PapyrusWorldStateBridge) {
        bridge.actorNatives.actorValueRuntime = { [weak game] in game?.actorValues.runtime }
        bridge.actorNatives.ragdollRuntime = { [weak game] in game?.ragdoll.runtime }
        bridge.actorNatives.combatRuntime = { [weak game] in game?.combat.loop }
        // Only the player tracks a draw state, so `IsWeaponDrawn` fails with a
        // reason for everyone else instead of claiming sheathed.
        bridge.actorNatives.weaponDrawState = { [weak game] key in
            guard key == .player else { return nil }
            return game?.combat.melee?.state.drawState
        }
        bridge.sessionNatives.conditionData = { [weak game] in
            game?.runtimeStateWorld.conditionData() ?? .empty
        }
        bridge.perceptionNatives
            .detection = { [weak game] in game?.perception.perceptionResolution() }
        bridge.sessionNatives.currentPackage = { [weak game] actor in
            game?.packages.runtime?.currentPackage(for: actor)?.package.formID
        }
        bridge.sessionNatives
            .packageTemplate = { [weak game] package in game?.packages.template(of: package) }
        bridge.perceptionNatives.lightLevel = { [weak game] feet in
            let body = SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight * 0.5)
            return game?.aiWorld.lightLevel(at: feet + body) ?? 1
        }
        bridge.sessionNatives.cellFog = { [weak self] cell, change in
            self?.changeFog(change, in: cell) ?? false
        }
        bridge.sessionNatives.havokMass = { [weak game] key in
            if let body = game?.streamer?.dynamicBodies.body(for: key) {
                return body.definition.mass
            }
            return game?.ragdoll.runtime?.world.ragdolls.first { $0.key == key }?
                .instance.bodies.reduce(0) { $0 + $1.definition.mass }
        }
        bridge.sessionNatives.publishTranslationPoses = { [weak game] poses in
            guard let game else { return }
            game.gameSession?.instancePoses.scriptedPoses = poses
                .reduce(into: [:]) { matrices, entry in
                    guard let formID = game.streamer?.referenceEntry(key: entry.key)?.formID
                    else { return }
                    matrices[formID.rawValue] = MatrixMath.placement(
                        position: entry.value.position, rotation: entry.value.rotation, scale: 1
                    )
                }
        }
        bridge.perceptionNatives.livePosition = { [weak game] key in
            guard let game else { return nil }
            guard key != .player else { return game.gameSession?.locomotion.status.feetPosition }
            return game.actorWorld.combatActor(key: key)?.feet
        }
    }

    /// Decoded once per base form, because each equip asks again.
    private static func itemScripts(
        _ lookup: PlacedRecordLookup?
    ) -> (ReferenceKey) -> [AttachedScript] {
        var cache: [ReferenceKey: [AttachedScript]] = [:]
        return { base in
            if let known = cache[base] {
                return known
            }
            let scripts = lookup?.scripts(ofBase: base) ?? []
            cache[base] = scripts
            return scripts
        }
    }

    private func wireSpellNatives(
        bridge: PapyrusWorldStateBridge,
        provider: WorldDataStores
    ) {
        bridge.magicNatives.casterRuntime = { [weak game] in game?.magic.caster }
        bridge.magicEffectStore = provider.magicEffectStore
        bridge.formListStore = provider.formListStore
        bridge.keywordStore = provider.locationStore?.keywords
        bridge.magicNatives.dispelEffects = { [weak game] holder, predicate in
            game?.magic.withEffects { $0.dispel(on: holder, where: predicate) } ?? 0
        }
        bridge.magicNatives.applySpellHit = { [weak game] hit in
            game?.magicWorld.applySpellHit(hit) ?? .none
        }
        bridge.magicNatives.trapSoul = { [weak game] victim, caster in
            guard case .trapped = game?.magic.trapSoul(of: victim, by: caster) else { return false }
            return true
        }
        wirePerkNatives(bridge: bridge)
    }

    /// Granting a perk reconciles its abilities in the same call.
    private func wirePerkNatives(bridge: PapyrusWorldStateBridge) {
        bridge.progressionNatives.mutatePerks = { [weak game] mutation, perk, actor in
            guard let game, let holder = game.actorWorld.actorValueHolder(for: actor) else {
                return false
            }
            return switch mutation {
            case .add: game.perks.add(perk, to: holder)
            case .remove: game.perks.remove(perk, from: holder)
            }
        }
        bridge.progressionNatives.perkOwnership = { [weak game] key in
            game?.perks.ownership(of: key)
        }
        bridge.progressionNatives.advanceSkill = { [weak game] advance, index, magnitude in
            guard let progression = game?.progression else { return false }
            return switch advance {
            case .advance: progression.advanceSkill(index, byUse: magnitude)
            case .increment: progression.incrementSkill(index)
            }
        }
        // A zero delta is the read `Game.GetPerkPoints` makes.
        bridge.progressionNatives.modifyPerkPoints = { [weak game] delta in
            game?.progression.modifyPerkPoints(by: delta)
        }
        bridge.crimeNatives.crimeReporter = { [weak game] in game?.crime.reporter }
        bridge.crimeNatives.arrestSession = { [weak game] in game?.crime }
        game.crime.scriptedOwner = { [weak bridge] key in bridge?.scriptedOwner(of: key) }
        let worldState = game.worldState
        game.crime.scriptedOwnerRevision = { [weak worldState] in
            worldState?.revision(of: [.scriptedState]) ?? 0
        }
        bridge.crimeNatives.showBarterMenu = { [weak game] actor in
            guard let game, game.inventory.vendors != nil else { return nil }
            let text = game.containerMenu.openBarter(with: actor)
            return (game.containerMenu.isOpen && game.containerMenu.vendor != nil, text)
        }
        game.factionWorld.wireNatives(bridge: bridge)
    }
}

extension ScriptWorldAdapter: ScriptWorld {
    var crosshairReference: FormID? {
        game.hud.interactionTarget?.interaction.reference
    }

    func referenceKey(formID: FormID) -> ReferenceKey? {
        game.streamer?.referenceEntry(formID: formID)?.key
    }

    var gameClock: GameClock? {
        game.gameSession?.gameClock
    }

    var playerLocation: ResolvedFormID?? {
        guard
            let streamer = game.streamer,
            let current = streamer.currentCellLocation,
            let scene = streamer.residentScene(at: current)
        else { return nil }
        return .some(game.runtimeStateWorld.location(of: scene))
    }
}
