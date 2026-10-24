// The app's answers to the session natives in `PapyrusGameNatives`: saves, quitting,
// fades, screen blood, god mode, the title backdrop, package locations, stuck arrows,
// impacts, forced ragdolls, cell resets, and model nodes.

import Foundation
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
        hooks.nodePosition = modelNodes.flatMap { nodes in
            { [weak self] key, name, then in
                self?.nodePosition(of: key, named: name, nodes: nodes, then: then) ?? .missing
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
        // The fade is instant: a fade out covers the world in black, a fade in uncovers it.
        hooks.fade = { [weak game] fade in
            try? game?.renderer?.setLoadingCover(fade.fadingOut ? [] : nil)
        }
        hooks
            .showTitleSequenceMenu = { [weak game] shown in
                game?.menuWorld.showTitleBackdrop(shown)
            }
        hooks.screenBlood = { [weak game] count in game?.effects.splatterScreen(count: count) }
        hooks.clearTempEffects = { [weak game] in game?.effects.clearTemporaryBlood() }
        hooks.takeScreenshot = { [weak game] name in
            guard let renderer = game?.renderer else { return false }
            return Self.writeScreenshot(named: name, renderer: renderer)
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
        hooks.setGodMode = { [weak game] isOn in game?.actorValues.runtime?.godMode.isOn = isOn }
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
        hooks.playImpact = { [weak game] dataSet, key in
            guard
                let game, let impacts, let id = game.scripts.bridge?.localFormID(of: dataSet),
                let impact = impacts.resolve(dataSet: id, material: nil),
                let position = game.scripts.bridge?.referenceState(for: key)?.transform.position
            else { return false }
            game.combatWorld.playImpact(impact, at: position)
            return true
        }
        hooks.resetCell = { [weak game] cell in
            guard
                let game, let reset = game.gameSession?.cellReset,
                let id = game.scripts.bridge?.localFormID(of: cell)
            else { return false }
            reset.flagForReset(.interior(id))
            return true
        }
    }

    private static func writeScreenshot(named name: String, renderer: Renderer) -> Bool {
        guard
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)
                .first,
            let texture = try? renderer.renderOffscreen(width: 1920, height: 1080)
        else { return false }
        let file = (name.isEmpty ? "ScreenShot" : name) + ".png"
        let url = pictures.appending(path: "OpenSky").appending(path: file)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return (try? FrameScreenshot.write(texture: texture, to: url)) != nil
    }
}
