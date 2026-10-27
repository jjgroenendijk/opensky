// The app's answers to the session natives in `PapyrusGameNatives`: saves, quitting,
// fades, screen blood, god mode, the title backdrop, package locations, stuck arrows,
// impacts, forced ragdolls, cell resets, and model nodes.

import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

extension ScriptWorldAdapter {
    func wireGameNatives(bridge: PapyrusWorldStateBridge, provider: WorldDataStores) {
        var hooks = PapyrusGameNatives()
        wireSaveAndScreen(&hooks)
        wirePlayerRules(&hooks)
        wireReferenceRules(&hooks, provider: provider)
        wireSounds(&hooks)
        wirePaths(&hooks)
        hooks.nodeTransform = modelNodes.flatMap { nodes in
            { [weak self] key, name, then in
                self?.nodeTransform(of: key, named: name, nodes: nodes, then: then) ?? .missing
            }
        }
        bridge.gameNatives = hooks
    }

    private func wireSaveAndScreen(_ hooks: inout PapyrusGameNatives) {
        hooks.requestSave = { [weak game] autosave in
            game?.saveGames.requestSave(autosave: autosave) ?? false
        }
        hooks.quitToMainMenu = { [weak game] in game?.quitToMainMenu() }
        hooks.quitGame = { [weak game] in game?.quitApplication() }
        hooks.fade = { [weak game] fade in
            game?.gameSession?.imageSpace.screenFade.start(
                fadingOut: fade.fadingOut, black: fade.black,
                delay: fade.secondsBeforeFade, duration: fade.duration
            )
        }
        // The title sequence draws its titles over the world. That movie is not built,
        // so the calls change nothing rather than hide the world behind the menu logo.
        hooks.showTitleSequenceMenu = { _ in }
        hooks.screenBlood = { [weak game] count in game?.effects.splatterScreen(count: count) }
        hooks.clearTempEffects = { [weak game] in game?.effects.clearTemporaryBlood() }
        hooks.takeScreenshot = { [weak game] name in
            guard let game, let renderer = game.renderer else { return false }
            let size = (game.hostView as? MTKView)?.drawableSize ?? .zero
            return Self.writeScreenshot(named: name, renderer: renderer, size: size)
        }
        hooks.toggleCollisions = { [weak game] in
            guard let session = game?.gameSession else { return }
            session.setMovementMode(session.movementMode == .fly ? .walk : .fly)
        }
        hooks.centerOnCell = { [weak game] cell in
            game?.menuWorld.teleportPlayer(.cell(cell), openingRaceMenu: false)
            return game != nil
        }
        hooks.showFirstPersonGeometry = { [weak game] shown in
            game?.gameSession?.firstPersonArmsEnabled = shown
        }
    }

    private func wirePlayerRules(_ hooks: inout PapyrusGameNatives) {
        hooks.setGodMode = { [weak game] isOn in game?.actorValues.runtime?.godMode = isOn }
        hooks.setFootIK = { [weak game] isOn in
            game?.actorGraphs.footIk = isOn
            game?.gameSession?.locomotion.footIk = isOn
        }
        hooks.clearPrison = { [weak game] in game?.crime.clearPrison() }
        hooks.setPlayerReportsCrime = { [weak game] reports in
            game?.crime.reporter?.runtime.reportsPlayerCrimes = reports
        }
        hooks.playerGrabbedReference = { [weak game] in game?.magic.playerGrabbedReference }
        hooks.packageLocation = { [weak game] actor in game?.packages.packageLocation(of: actor) }
        hooks.forceRagdoll = { [weak game] key in
            game?.ragdoll.runtime?.activate(key, instant: true) ?? false
        }
    }

    private func wireReferenceRules(_ hooks: inout PapyrusGameNatives, provider: WorldDataStores) {
        hooks.clearExtraArrows = { [weak game] actor in
            guard let game, let host = game.streamer?.referenceEntry(key: actor)?.formID else {
                return 0
            }
            return game.combat.archery?.projectiles.removeArrows(stuckIn: host) ?? 0
        }
        let impacts = provider.footstepStore.map(MeleeImpactResolver.init(footsteps:))
        hooks.playImpact = { [weak self] dataSet, pick in
            guard
                let self, let impacts, let id = game.scripts.bridge?.localFormID(of: dataSet),
                let hit = impactHit(of: pick),
                let impact = impacts.resolve(dataSet: id, material: hit.material)
            else { return false }
            game.combatWorld.playImpact(impact, at: hit.position)
            return true
        }
        // A script names a cell it is in or next to, so an exterior one is loaded.
        hooks.resetCell = { [weak game] cell in
            guard
                let game, let reset = game.gameSession?.cellReset,
                let id = game.scripts.bridge?.localFormID(of: cell)
            else { return false }
            let exterior = game.streamer?.composition.cells.values
                .first { !$0.isInterior && $0.cellFormID == id }.flatMap(\.location)
            reset.flagForReset(exterior ?? .interior(id))
            return true
        }
    }

    private func wireSounds(_ hooks: inout PapyrusGameNatives) {
        hooks.playSound = { [weak game] sound, source, token in
            guard
                let game, let director = game.gameSession?.soundDirector,
                let id = game.scripts.bridge?.localFormID(of: sound),
                let position = game.scripts.bridge?.referenceState(for: source)?.transform.position
            else { return 0 }
            return director.playScriptSound(formID: id, at: position, waitToken: token)
        }
        hooks
            .stopSound = { [weak game] id in game?.gameSession?.soundDirector?.stopScriptSound(id) }
        hooks.setSoundVolume = { [weak game] id, volume in
            game?.gameSession?.soundDirector?.setScriptSoundVolume(id, volume)
        }
        hooks.setParticleGeometry = { [weak game] geometry, seconds in
            guard let session = game?.gameSession else { return }
            guard let geometry else {
                session.scriptParticles.remove(fadeOut: seconds)
                return
            }
            guard
                case let .plugin(plugin, objectID) = geometry,
                let record = session.imageSpaceLinks?.records.shaderParticles
                    .record(ResolvedFormID(plugin: plugin, objectID: objectID))?.record
            else { return }
            session.scriptParticles.apply(record, fadeIn: seconds)
        }
    }

    /// Answers each `Sound.PlayAndWait` whose sound ended. An answer the scheduler
    /// cannot take yet waits for the next frame.
    func answerSoundWaits() {
        if let director = game.gameSession?.soundDirector {
            soundWaitAnswers.merge(director.retireScriptSounds()) { first, _ in first }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        soundWaitAnswers = soundWaitAnswers.filter { token, played in
            !scheduler.answer(token, returning: .boolean(played))
        }
    }

    /// Where `PlayImpactEffect`'s pick meets a surface. A node not readable now picks
    /// from the reference. "Local" rotation is read as the node's turn inside the
    /// reference, not inside its parent node.
    private func impactHit(of pick: PapyrusImpactPick) -> ImpactPickHit? {
        guard
            let streamer = game.streamer,
            let state = game.scripts.bridge?.referenceState(for: pick.source)
        else { return nil }
        let node = pick.node.isEmpty ? nil : readyNode(of: pick.source, named: pick.node)
        let origin = node.map { simd_make_float3($0.world.columns.3) }
            ?? state.transform.position
        var direction = pick.direction
        if let node, pick.appliesNodeRotation {
            let turn = pick.usesNodeLocalRotation ? node.local : node.world
            let turned = turn * SIMD4(direction, 0)
            direction = SIMD3(turned.x, turned.y, turned.z)
        }
        let query = ShapeSweepQuery.sphere(
            center: origin, radius: 1, direction: direction, maximumDistance: pick.length
        )
        let solid = game.combatWorld.sweep(query).map {
            (
                distance: $0.distance,
                hit: ImpactPickHit(position: $0.position, material: $0.material)
            )
        }
        return ImpactPick.resolve(
            origin: origin, direction: direction, length: pick.length, staticHit: solid
        ) { point in
            streamer.sampleTerrain(at: point).map { (height: $0.height, material: $0.material) }
        }
    }

    /// The game writes into its install folder, which OpenSky keeps read-only, so the
    /// capture goes to the user's pictures instead.
    private static func writeScreenshot(
        named name: String, renderer: Renderer, size: CGSize
    ) -> Bool {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard
            width > 0, height > 0,
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)
                .first,
            let texture = try? renderer.renderOffscreen(width: width, height: height)
        else { return false }
        let file = (name.isEmpty ? "ScreenShot" : name) + ".png"
        let url = pictures.appending(path: "OpenSky").appending(path: file)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return (try? FrameScreenshot.write(texture: texture, to: url)) != nil
    }
}
