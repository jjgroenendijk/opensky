import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DialogueCameraWiringAdapter` reads from the session.
@MainActor
public protocol DialogueCameraWiringHost: AnyObject {
    var dialogueCamera: any DialogueCameraPort { get }
    var faceMorphs: any FaceMorphPort { get }
    var headTracking: any HeadTrackingPort { get }
    var renderer: (any RendererPort)? { get }
}

/// Part of `DialogueWorldAdapter`, over its own narrow host.
public struct DialogueCameraWiringAdapter {
    public let game: any DialogueCameraWiringHost
}

extension DialogueCameraWiringAdapter {}
