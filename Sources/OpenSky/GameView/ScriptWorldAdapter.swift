// App side of `ScriptCoordinator`: builds the world bridge, gives its natives
// their collaborators, binds script lifetime to cell streaming, and ticks the
// VM from the renderer. The panel logic lives in the coordinator.

import OpenSkyActors
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

final class ScriptWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// The streamer, the renderer, and the provider each feed the VM one way,
    /// so the engine never depends on it. Without compiled scripts there is no VM.
    func wirePapyrus(
        provider: any WorldDataProviding,
        renderer: Renderer,
        streamer: CellStreamer
    ) {
        guard
            let scriptSource = provider as? ScriptDataProviding,
            let fileSystem = scriptSource.scriptFileSystem
        else { return }
        let bridge = PapyrusWorldStateBridge(
            worldState: game.worldState, references: streamer,
            globals: game.runtimeState.globalStore
        )
        bridge.clockSource = { [weak renderer] in renderer?.gameClock }
        wireActorNatives(bridge: bridge)
        wireSpellNatives(bridge: bridge, provider: provider)
        let resolver = scriptSource.scriptFormIDResolver
        bridge.formIDResolver = resolver
        let world = game.scripts.start(bridge: bridge, fileSystem: fileSystem)
        streamer.onInteraction.add { [weak bridge] event in
            bridge?.handleInteraction(event)
        }
        // The streamer tests trigger volumes once per walk-mode frame; each edge
        // queues one event per script on the volume's reference.
        streamer.onTriggerTransition.add { [weak bridge] event in
            bridge?.handleTriggerTransition(event)
        }
        wireQuests(provider: provider)
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
        renderer.onWorldUpdate = { [weak self] delta in
            self?.game.scripts.advance(delta: delta)
        }
    }

    /// Without a QUST index every `Quest` native fails with
    /// `PapyrusQuestBridgeError.noQuestData`.
    private func wireQuests(provider: any WorldDataProviding) {
        guard let store = (provider as? QuestDataProviding)?.questStore else { return }
        game.scripts.attachQuests(QuestRuntime(
            store: game.worldState,
            quests: store,
            locations: (provider as? LocationDataProviding)?.locationStore
        ))
    }

    /// Getters, not captured values: the runtimes behind them are wired after
    /// this step.
    private func wireActorNatives(bridge: PapyrusWorldStateBridge) {
        bridge.actorValueRuntime = { [weak game] in game?.actorValues.runtime }
        bridge.ragdollRuntime = { [weak game] in game?.ragdoll.runtime }
        bridge.combatRuntime = { [weak game] in game?.combat.loop }
        // Only the player tracks a draw state, so `IsWeaponDrawn` fails with a
        // reason for everyone else instead of claiming sheathed.
        bridge.weaponDrawState = { [weak game] key in
            guard key == .player else { return nil }
            return game?.combat.melee?.state.drawState
        }
    }

    private func wireSpellNatives(
        bridge: PapyrusWorldStateBridge,
        provider: any WorldDataProviding
    ) {
        bridge.casterRuntime = { [weak game] in game?.magic.caster }
        bridge.magicEffectStore = (provider as? MagicDataProviding)?.magicEffectStore
        bridge.formListStore = (provider as? FactionDataProviding)?.formListStore
        bridge.dispelEffects = { [weak game] holder, predicate in
            game?.magic.withEffects { $0.dispel(on: holder, where: predicate) } ?? 0
        }
        bridge.applySpellHit = { [weak game] hit in
            game?.magic.applySpellHit(hit) ?? .none
        }
        wirePerkNatives(bridge: bridge)
    }

    /// Granting a perk reconciles its abilities in the same call.
    private func wirePerkNatives(bridge: PapyrusWorldStateBridge) {
        bridge.mutatePerks = { [weak game] mutation, perk, actor in
            guard let game, let holder = game.actorWorld.actorValueHolder(for: actor) else {
                return false
            }
            return switch mutation {
            case .add: game.perks.add(perk, to: holder)
            case .remove: game.perks.remove(perk, from: holder)
            }
        }
        bridge.perkOwnership = { [weak game] key in
            game?.perks.ownership(of: key)
        }
        bridge.advanceSkill = { [weak game] advance, index, magnitude in
            guard let progression = game?.progression else { return false }
            return switch advance {
            case .advance: progression.advanceSkill(index, byUse: magnitude)
            case .increment: progression.incrementSkill(index)
            }
        }
        // A zero delta is the read `Game.GetPerkPoints` makes.
        bridge.modifyPerkPoints = { [weak game] delta in
            game?.progression.modifyPerkPoints(by: delta)
        }
        bridge.crimeReporter = { [weak game] in game?.crime.reporter }
        bridge.arrestSession = { [weak game] in game?.crime }
        bridge.showBarterMenu = { [weak game] actor in
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
        game.renderer?.gameClock
    }
}
