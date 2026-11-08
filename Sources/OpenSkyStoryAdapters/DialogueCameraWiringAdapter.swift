import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
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
    public unowned let owner: DialogueWorldAdapter
    public unowned let game: any DialogueCameraWiringHost
}

extension DialogueCameraWiringAdapter {}
