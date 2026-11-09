import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `DialogueWorldAdapter`.
extension DialogueWorldAdapter {
    public func speakerLabel(for speaker: ReferenceKey) -> String {
        speakers.speakerLabel(for: speaker)
    }

    public func residentVoiceTypes() -> [ReferenceKey: FormID] {
        speakers.residentVoiceTypes()
    }

    public func headPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        speakers.headPosition(of: actor)
    }

    public func run(_ commands: [DialogueCommand]) {
        outcomes.run(commands)
    }
}
