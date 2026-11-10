import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
public import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldSettingsApplyAdapter` reads from the session.
@MainActor
public protocol MenuWorldSettingsApplyHost: AnyObject, SendableMetatype {
    var audio: any AudioPort { get }
    var cameraInput: any CameraInputStatePort { get }
    var combat: any CombatPort { get }
    var hud: any HUDPort { get }
    var renderer: (any RendererPort)? { get }
    var subtitles: any SubtitlePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldSettingsApplyAdapter {
    public let game: any MenuWorldSettingsApplyHost
    public let state: MenuPartState
}

extension MenuWorldSettingsApplyAdapter {
    public func applyAudioEnabled(_ enabled: Bool) {
        game.audio.audioEnabled = enabled
    }

    public func applyMasterVolume(_ volume: Float) {
        game.audio.audioMasterVolume = volume
    }

    public func applyCategoryVolume(_ volume: Float, soundCategoryEditorID: String) {
        guard
            let category = AudioCategory.allCases.first(where: {
                $0.soundCategoryEditorID == soundCategoryEditorID
            }) else { return }
        game.audio.setAudioVolume(volume, for: category)
    }

    public func applyLook(sensitivity: Float, inverted: Bool) {
        game.cameraInput.lookScale = sensitivity
        game.cameraInput.invertLook = inverted
    }

    public func applyHUD(_ hud: PlayerHUDSettings) {
        game.hud.update {
            $0.crosshairEnabled = hud.crosshair
            $0.compassEnabled = hud.compass
            $0.markersEnabled = hud.floatingMarkers
        }
        game.renderer?.swfOpacity = hud.opacity
        game.subtitles.apply(hud.subtitles)
    }

    public func applyDifficulty(index: Int) {
        game.combat.difficulty = DifficultyLevel(index: index)
    }

    public func applyBindings(_ bindings: InputBindings) {
        state.applyViewBindings(bindings)
    }
}
