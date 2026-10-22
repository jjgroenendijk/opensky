// The Face Morphs panel's seam: face weights, the automatic face switches, and head
// tracking. Each switch also writes its persisted player setting.

import OpenSkyActorPresentation
import OpenSkyGameData

extension GameViewController: FaceMorphControlProviding {
    var faceMorphSnapshot: FaceMorphControlSnapshot {
        faceMorphs.faceMorphSnapshot
    }

    var automaticBlinkingEnabled: Bool {
        get { faceMorphs.automaticBlinkingEnabled }
        set {
            faceMorphs.automaticBlinkingEnabled = newValue
            playerSettingsStore.set(.characterBlinking, to: newValue ? 1 : 0)
        }
    }

    var eyeMovementEnabled: Bool {
        get { faceMorphs.eyeMovementEnabled }
        set {
            faceMorphs.eyeMovementEnabled = newValue
            playerSettingsStore.set(.characterEyeMovement, to: newValue ? 1 : 0)
        }
    }

    var dialogueExpressionsEnabled: Bool {
        get { faceMorphs.dialogueExpressionsEnabled }
        set {
            faceMorphs.dialogueExpressionsEnabled = newValue
            playerSettingsStore.set(.characterDialogueExpressions, to: newValue ? 1 : 0)
        }
    }

    var headTrackingEnabled: Bool {
        get { headTracking.isEnabled }
        set {
            headTracking.isEnabled = newValue
            playerSettingsStore.set(.characterHeadTracking, to: newValue ? 1 : 0)
        }
    }

    var headTrackingReadout: String {
        headTracking.readout(for: dialogueMenu.speakerOrTarget)
    }

    func setFaceMorphWeight(_ weight: Float, target: String) {
        faceMorphs.setFaceMorphWeight(weight, target: target)
    }

    func resetFaceMorphWeights() {
        faceMorphs.resetFaceMorphWeights()
    }
}
