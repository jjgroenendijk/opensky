// The detection value, as arithmetic (issue #202, roadmap item 16.6).
//
// A pure function of numbers, deliberately, exactly like `ProjectileFlight`: no
// world, no clock, no collision, no state. That is what makes "sneaking versus
// standing changes the accumulation rate" a plain assertion over two literals,
// and it is why the geometry that decides `hasLineOfSight` and `isInViewCone`
// lives next door in `PerceptionSight` instead of here.
//
// ## The shape, and where it came from
//
// UESP "Skyrim:Sneak", section "Remaining Undetected", states the whole thing:
//
//     Detection Value = fSneakBaseValue
//         + (Sound factor + Visual factor + Noticer skill factor) * attenuation
//         + (Noticer skill factor - Sneaker skill factor)
//     attenuation = ((fSneakMaxDistance - distance) / fSneakMaxDistance) ^ exponent
//     Sound Factor = fSneakSoundsMult * (Movement + Action)
//                    * (1 with line of sight, fSneakSoundLosMult without)
//     Movement     = (fSneakEquippedWeightBase + fSneakEquippedWeightMult * weight)
//                    * (fSneakRunningMult if running) * muffle,  0 when not moving
//     Action       = ActionSound * fSneakActionMult
//
// That shape is implemented as written. The constants come from the install
// where the install has them (`DetectionSettings`), and the *visual* factor is
// the one term UESP describes only qualitatively — it names light level as the
// driver and light level is a gap here — so its shape is OpenSky's and says so.
//
// ## The four pinned inputs, and why they are pinned rather than guessed
//
// Light level, muffle, action sounds and both skill levels are inputs this
// engine cannot supply today. Each one is a named constant below with the
// documented neutral value it is pinned at, so a reader can see exactly what is
// missing and what filling it would change. None of them is approximated with a
// plausible-looking substitute: a wrong number that moves is worse than a
// stated constant that does not, because only one of the two is visible.
//
// Documented in docs/engine/detection.md.

import Foundation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

nonisolated public enum DetectionFormula: Sendable {
    /// How lit the target is, 1 being fully lit. Pinned: nothing samples scene
    /// light per actor yet. `fSneakLightMult`, `fSneakLightExteriorMult` and
    /// `fDetectionSneakLightMod` are the settings a real light term would read.
    public static let pinnedLightFactor: Float = 1
    /// The Muffle magnitude on the target, 1 being unmuffled. Pinned: no magic
    /// effects exist yet.
    public static let pinnedMuffle: Float = 1
    /// The target's action sound this instant. Pinned: no attack, cast or shout
    /// reports one to perception yet.
    public static let pinnedActionSound: Float = 0
    /// Both skill levels. `ActorValueIdentity` names Sneak as vanilla actor
    /// value 15, and item 15.3 stores three of the 164 — health, magicka and
    /// stamina — so neither the sneaker's Sneak nor the noticer's perception is
    /// readable through `ActorValueRuntime` today. Pinned at the vanilla
    /// starting skill level, which UESP "Skyrim:Skills" states is 15 for every
    /// skill before racial bonuses.
    ///
    /// Pinning both at the same number is what makes the formula's trailing
    /// `(Noticer - Sneaker)` term exactly zero, so the one place a skill still
    /// shows up is the attenuated noticer term.
    public static let pinnedSkillLevel: Float = 15

    /// The range this pair's senses attenuate over, world units.
    public static func maximumDistance(settings: DetectionSettings, isExterior: Bool) -> Float {
        let base = max(0, settings.maxDistance.value)
        return isExterior ? base * max(0, settings.exteriorDistanceMult.value) : base
    }

    /// `((max - distance) / max) ^ exponent`, clamped to 0...1.
    ///
    /// Zero at and beyond the maximum distance, and 1 at zero distance. A
    /// non-finite or negative distance attenuates to nothing rather than
    /// producing a NaN that would poison every comparison downstream.
    public static func attenuation(
        distance: Float,
        settings: DetectionSettings,
        isExterior: Bool
    ) -> Float {
        let maximum = maximumDistance(settings: settings, isExterior: isExterior)
        guard distance.isFinite, distance >= 0, maximum > 0, distance < maximum else {
            return 0
        }
        let linear = (maximum - distance) / maximum
        return powf(linear, max(0, settings.distanceAttenuationExponent.value))
    }

    /// What movement at `gait` multiplies the target's noise by.
    ///
    /// Only the running multiplier is vanilla's. Standing still is vanilla's
    /// rule with no constant attached, and the sneak and sprint steps either
    /// side of walking are OpenSky's — see `DetectionSettings`. Swimming is
    /// deliberately given walking's multiplier rather than a fourth constant
    /// nothing measured.
    public static func movementMultiplier(
        gait: LocomotionGait?,
        settings: DetectionSettings
    ) -> Float {
        switch gait {
        case .none: 0
        case .sneak: max(0, settings.sneakMovementMult.value)
        case .walk, .swim: 1
        case .run: max(0, settings.runningMult.value)
        case .sprint: max(0, settings.sprintMovementMult.value)
        }
    }

    /// The sound term, before distance attenuation.
    public static func soundFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        let weight = inputs.equippedWeight.isFinite ? max(0, inputs.equippedWeight) : 0
        let carried = max(0, settings.equippedWeightBase.value)
            + max(0, settings.equippedWeightMult.value) * weight
        let movement = carried
            * movementMultiplier(gait: inputs.gait, settings: settings)
            * pinnedMuffle
        let action = pinnedActionSound * settings.actionMult.value
        let occlusion = inputs.hasLineOfSight ? 1 : max(0, settings.soundLosMult.value)
        return settings.soundsMult.value * (movement + action) * occlusion
    }

    /// The visual term, before distance attenuation. Zero without a clear sight
    /// line or outside the cone; there is no partial seeing in this model, and
    /// the docs page says so.
    public static func visualFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        guard inputs.hasLineOfSight, inputs.isInViewCone else { return 0 }
        let crouch = inputs.isSneaking ? max(0, settings.sneakVisualMult.value) : 1
        return max(0, settings.visualBaseValue.value) * pinnedLightFactor * crouch
    }

    /// The observer's skill term, from the pinned skill level.
    public static func skillFactor(settings: DetectionSettings) -> Float {
        let clamped = min(
            max(pinnedSkillLevel, settings.perceptionSkillMin.value),
            settings.perceptionSkillMax.value
        )
        return clamped * settings.skillMult.value
    }

    /// The whole formula, with its terms.
    public static func breakdown(
        inputs: DetectionInputs,
        settings: DetectionSettings
    ) -> DetectionBreakdown {
        let attenuation = attenuation(
            distance: inputs.distance, settings: settings, isExterior: inputs.isExterior
        )
        let sound = soundFactor(inputs: inputs, settings: settings)
        let visual = visualFactor(inputs: inputs, settings: settings)
        let skill = skillFactor(settings: settings)
        // The trailing `(Noticer - Sneaker)` term is omitted rather than added
        // as a literal zero: both skills are pinned to one constant, so it is
        // exactly zero by construction and writing it would suggest otherwise.
        let value = settings.sneakBaseValue.value + (sound + visual + skill) * attenuation
        return DetectionBreakdown(
            soundFactor: sound,
            visualFactor: visual,
            skillFactor: skill,
            distanceAttenuation: attenuation,
            value: value.isFinite ? value : settings.sneakBaseValue.value
        )
    }

    /// How far a target moving at `gait` can be heard, world units: the
    /// distance at which the sound and skill terms alone exactly cancel
    /// `fSneakBaseValue`.
    ///
    /// Closed form rather than a search, because the attenuation is invertible:
    /// with `needed = -base / (sound + skill)` the radius is
    /// `max * (1 - needed^(1/exponent))`. Zero when even a touching target is
    /// too quiet to notice, which is a real answer for a crouching one.
    ///
    /// Nothing in the pass consumes this — the attenuated sound term already
    /// produces the behaviour. It exists because "a gait-based noise radius" is
    /// what the milestone asks for in world units, and this is that number.
    public static func noiseRadius(
        gait: LocomotionGait?,
        settings: DetectionSettings,
        isExterior: Bool,
        hasLineOfSight: Bool = true,
        equippedWeight: Float = 0
    ) -> Float {
        let inputs = DetectionInputs(
            distance: 0,
            hasLineOfSight: hasLineOfSight,
            isInViewCone: false,
            isExterior: isExterior,
            gait: gait,
            equippedWeight: equippedWeight
        )
        let audible = soundFactor(inputs: inputs, settings: settings) + skillFactor(
            settings: settings
        )
        let deficit = -settings.sneakBaseValue.value
        let exponent = max(0, settings.distanceAttenuationExponent.value)
        guard audible > 0, deficit > 0, exponent > 0, audible > deficit else {
            return audible > 0 && deficit <= 0
                ? maximumDistance(settings: settings, isExterior: isExterior)
                : 0
        }
        let needed = powf(deficit / audible, 1 / exponent)
        return maximumDistance(settings: settings, isExterior: isExterior) * (1 - needed)
    }
}
