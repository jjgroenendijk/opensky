// The reporting half of `DetectionSettings`. One ordered table, so
// `openskycli gmst detection` and the panel show the same rows in the same order.

import Foundation
import OpenSkyPhysics

nonisolated extension DetectionSettings {
    /// Every setting paired with the name it is addressed by. Load-order
    /// settings first, in formula order, then OpenSky's own.
    public var report: [(editorID: String, setting: MovementSetting)] {
        [
            ("fSneakBaseValue", sneakBaseValue),
            ("fSneakMaxDistance", maxDistance),
            ("fSneakExteriorDistanceMult", exteriorDistanceMult),
            ("fSneakSoundsMult", soundsMult),
            ("fSneakSoundLosMult", soundLosMult),
            ("fSneakRunningMult", runningMult),
            ("fSneakActionMult", actionMult),
            ("fSneakSkillMult", skillMult),
            ("fSneakPerceptionSkillMin", perceptionSkillMin),
            ("fSneakPerceptionSkillMax", perceptionSkillMax),
            ("iSoundLevelSilent", silentActionSound),
            ("distanceAttenuationExponent", distanceAttenuationExponent),
            ("equippedWeightBase", equippedWeightBase),
            ("equippedWeightMult", equippedWeightMult),
            ("sneakMovementMult", sneakMovementMult),
            ("sprintMovementMult", sprintMovementMult),
            ("viewConeHalfAngleDegrees", viewConeHalfAngleDegrees),
            ("visualBaseValue", visualBaseValue),
            ("sneakVisualMult", sneakVisualMult),
            ("normalActionSound", normalActionSound),
            ("loudActionSound", loudActionSound),
            ("veryLoudActionSound", veryLoudActionSound),
            ("fullLightLuminance", fullLightLuminance),
            ("fullDetectionValue", fullDetectionValue),
            ("gainPerSecond", gainPerSecond),
            ("decayPerSecond", decayPerSecond),
            ("suspiciousLevel", suspiciousLevel),
            ("detectedLevel", detectedLevel)
        ]
    }
}
