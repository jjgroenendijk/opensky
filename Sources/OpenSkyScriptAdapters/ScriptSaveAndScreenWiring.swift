// `ScriptSessionBindingsAdapter` joins the started session: what `wireSaveAndScreen` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Connects `ScriptSessionBindingsAdapter` to the started session.
public struct ScriptSaveAndScreenWiring {
    public init(_ adapter: ScriptSessionBindingsAdapter, _ hooks: inout PapyrusGameNatives) {
        hooks.requestSave = { [weak game = adapter.game] autosave in
            game?.saveGames.requestSave(autosave: autosave) ?? false
        }
        hooks.quitToMainMenu = { [weak game = adapter.game] in game?.quitToMainMenu() }
        hooks.quitGame = { [weak game = adapter.game] in game?.quitApplication() }
        hooks.fade = { [weak game = adapter.game] fade in
            game?.gameSession?.imageSpace.screenFade.start(
                fadingOut: fade.fadingOut, black: fade.black,
                delay: fade.secondsBeforeFade, duration: fade.duration
            )
        }
        hooks
            .showTitleSequenceMenu = { [weak game = adapter.game] shown in
                game?.titleSequence.show(shown)
            }
        hooks
            .startTitleSequence = { [weak game = adapter.game] name in
                _ = game?.titleSequence.start(name)
            }
        hooks
            .screenBlood = { [weak game = adapter.game] count in
                game?.effects.splatterScreen(count: count)
            }
        hooks
            .clearTempEffects = { [weak game = adapter.game] in
                game?.effects.clearTemporaryBlood()
            }
        hooks.takeScreenshot = { [weak game = adapter.game] name in
            guard let game, let renderer = game.renderer else { return false }
            let size = game.drawableSize
            return ScriptSessionBindingsAdapter.writeScreenshot(
                named: name,
                renderer: renderer,
                size: size
            )
        }
        hooks.toggleCollisions = { [weak game = adapter.game] in
            guard let session = game?.gameSession else { return }
            session.setMovementMode(session.movementMode == .fly ? .walk : .fly)
        }
        hooks.centerOnCell = { [weak game = adapter.game] cell in
            game?.menuWorld.teleportPlayer(.cell(cell), openingRaceMenu: false)
            return game != nil
        }
        hooks.showFirstPersonGeometry = { [weak game = adapter.game] shown in
            game?.gameSession?.firstPersonArmsEnabled = shown
        }
    }
}
