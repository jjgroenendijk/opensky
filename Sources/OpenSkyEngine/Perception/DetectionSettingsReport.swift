// The reporting half of `DetectionSettings` (issue #202), split off so the
// settings type itself stays a list of fields and their provenance.
//
// One ordered table rather than a printer per consumer: `openskycli gmst
// detection` and the panel readout show the same rows in the same order, so a
// number a user reads in the app is the number a maintainer greps in a CLI
// transcript.

import Foundation

nonisolated extension DetectionSettings {
    /// Every setting paired with the name it is addressed by. Load-order
    /// settings first, in formula order, then OpenSky's own.
    var report: [(editorID: String, setting: MovementSetting)] {
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
            ("distanceAttenuationExponent", distanceAttenuationExponent),
            ("equippedWeightBase", equippedWeightBase),
            ("equippedWeightMult", equippedWeightMult),
            ("sneakMovementMult", sneakMovementMult),
            ("sprintMovementMult", sprintMovementMult),
            ("viewConeHalfAngleDegrees", viewConeHalfAngleDegrees),
            ("visualBaseValue", visualBaseValue),
            ("sneakVisualMult", sneakVisualMult),
            ("fullDetectionValue", fullDetectionValue),
            ("gainPerSecond", gainPerSecond),
            ("decayPerSecond", decayPerSecond),
            ("suspiciousLevel", suspiciousLevel),
            ("detectedLevel", detectedLevel)
        ]
    }
}
