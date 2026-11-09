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
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Witnesses that forward to the narrow parts of `MessageWorldAdapter`.
extension MessageWorldAdapter {
    public var renderer: (any RendererPort)? {
        cameraEffects.renderer
    }

    public var viewCamera: FreeFlyCamera? {
        cameraEffects.viewCamera
    }

    public var uiScene: UIScene {
        get { cameraEffects.uiScene }
        set { cameraEffects.uiScene = newValue }
    }

    public func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool {
        cameraEffects.shakeCamera(source: source, strength: strength, duration: duration)
    }

    public func forceCameraMode(firstPerson: Bool) -> Bool {
        cameraEffects.forceCameraMode(firstPerson: firstPerson)
    }
}
