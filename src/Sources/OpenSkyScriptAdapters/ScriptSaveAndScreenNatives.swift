// The Papyrus natives `ScriptSessionBindingsAdapter` fills as the bridge is built.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
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

extension ScriptSessionBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillSaveAndScreen(_ hooks: inout PapyrusGameNatives) {
        hooks.requestSave = { [weak game = self.game] autosave in
            game?.saveGames.requestSave(autosave: autosave) ?? false
        }
        hooks.quitToMainMenu = { [weak game = self.game] in game?.quitToMainMenu() }
        hooks.quitGame = { [weak game = self.game] in game?.quitApplication() }
        hooks.fade = { [weak game = self.game] fade in
            game?.gameSession?.imageSpace.screenFade.start(
                fadingOut: fade.fadingOut, black: fade.black,
                delay: fade.secondsBeforeFade, duration: fade.duration
            )
        }
        hooks
            .showTitleSequenceMenu = { [weak game = self.game] shown in
                game?.titleSequence.show(shown)
            }
        hooks
            .startTitleSequence = { [weak game = self.game] name in
                _ = game?.titleSequence.start(name)
            }
        hooks
            .screenBlood = { [weak game = self.game] count in
                game?.effects.splatterScreen(count: count)
            }
        hooks
            .clearTempEffects = { [weak game = self.game] in
                game?.effects.clearTemporaryBlood()
            }
        hooks.takeScreenshot = { [weak game = self.game] name in
            guard let game, let renderer = game.renderer else { return false }
            let size = game.drawableSize
            return ScriptSessionBindingsAdapter.writeScreenshot(
                named: name,
                renderer: renderer,
                size: size
            )
        }
        hooks.toggleCollisions = { [weak game = self.game] in
            guard let session = game?.gameSession else { return }
            session.setMovementMode(session.movementMode == .fly ? .walk : .fly)
        }
        hooks.centerOnCell = { [weak game = self.game] cell in
            game?.menuWorld.teleportPlayer(.cell(cell), openingRaceMenu: false)
            return game != nil
        }
        hooks.showFirstPersonGeometry = { [weak game = self.game] shown in
            game?.gameSession?.firstPersonArmsEnabled = shown
        }
    }
}
