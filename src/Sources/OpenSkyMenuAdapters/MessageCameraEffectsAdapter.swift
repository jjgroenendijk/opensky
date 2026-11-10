import Foundation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyCells
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyQuestsInterface
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MessageCameraEffectsAdapter` reads from the session.
@MainActor
public protocol MessageCameraEffectsHost: AnyObject, SendableMetatype {
    var cinematicCamera: any CinematicCameraPort { get }
    var cinematicWorld: any CinematicCameraWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
}

/// Part of `MessageWorldAdapter`, over its own narrow host.
public struct MessageCameraEffectsAdapter {
    public let game: any MessageCameraEffectsHost
}

extension MessageCameraEffectsAdapter {
    var renderer: (any RendererPort)? {
        game.renderer
    }

    public var viewCamera: FreeFlyCamera? {
        game.gameSession?.freeFlyCamera
    }

    var uiScene: UIScene {
        get { game.gameSession?.uiScene ?? .empty }
        nonmutating set { game.gameSession?.uiScene = newValue }
    }

    public func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool {
        let position = source.flatMap { game.cinematicWorld.anchorPosition(of: $0) }
        return game.cinematicCamera.startShake(
            source: position,
            strength: strength,
            duration: duration
        )
    }

    public func forceCameraMode(firstPerson: Bool) -> Bool {
        guard
            let gameSession = game.gameSession,
            gameSession.movementMode.isPlayerControlled else { return false }
        gameSession.setMovementMode(firstPerson ? .walk : .thirdPerson)
        return true
    }
}
