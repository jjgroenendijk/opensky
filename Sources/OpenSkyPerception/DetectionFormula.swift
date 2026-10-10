// The detection value, as pure arithmetic. The shape is UESP "Skyrim:Sneak",
// "Remaining Undetected", with constants from `DetectionSettings`. The visual
// factor's shape is ours, because UESP describes it only in words.
// See docs/engine/detection.md.

import Foundation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

nonisolated public enum DetectionFormula: Sendable {
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

    /// What movement at `gait` multiplies the target's noise by. Only the running
    /// multiplier is vanilla's; sneak and sprint are ours (`DetectionSettings`).
    /// Swimming uses walking's.
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

    /// The sound term, before distance attenuation. Muffle scales the armour
    /// part only (UESP "Skyrim:Muffle (effect)"): a silenced target still
    /// makes the base noise of its own steps.
    public static func soundFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        let traits = inputs.traits
        let weight = finiteNonNegative(traits.equippedWeight)
        let unmuffled = 1 - min(finiteNonNegative(traits.muffle), 1)
        let carried = max(0, settings.equippedWeightBase.value)
            + max(0, settings.equippedWeightMult.value) * weight * unmuffled
        let movement = carried * movementMultiplier(gait: inputs.gait, settings: settings)
        let action = finiteNonNegative(traits.actionSound) * settings.actionMult.value
        let occlusion = inputs.hasLineOfSight ? 1 : max(0, settings.soundLosMult.value)
        return settings.soundsMult.value * (movement + action) * occlusion
    }

    /// The visual term, before distance attenuation. Zero without a clear sight
    /// line or outside the cone; there is no partial seeing in this model, and
    /// the docs page says so.
    public static func visualFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        guard inputs.hasLineOfSight, inputs.isInViewCone, !inputs.traits.isInvisible else {
            return 0
        }
        let crouch = inputs.isSneaking ? max(0, settings.sneakVisualMult.value) : 1
        let light = min(finiteNonNegative(inputs.traits.lightLevel), 1)
        return max(0, settings.visualBaseValue.value) * light * crouch
    }

    /// One skill level, clamped and weighted into a skill factor.
    public static func skillFactor(
        level: Float = DetectionTargetTraits.startingSkill,
        settings: DetectionSettings
    ) -> Float {
        let level = level.isFinite ? level : DetectionTargetTraits.startingSkill
        let clamped = min(
            max(level, settings.perceptionSkillMin.value),
            settings.perceptionSkillMax.value
        )
        return clamped * settings.skillMult.value
    }

    private static func finiteNonNegative(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
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
        let noticer = skillFactor(level: inputs.noticerSkill, settings: settings)
        let sneaker = skillFactor(level: inputs.traits.sneakSkill, settings: settings)
        let value = settings.sneakBaseValue.value
            + (sound + visual + noticer) * attenuation
            + (noticer - sneaker)
        return DetectionBreakdown(
            soundFactor: sound,
            visualFactor: visual,
            value: value.isFinite ? value : settings.sneakBaseValue.value
        )
    }

    /// How far a target moving at `gait` can be heard, in world units: where the
    /// sound and skill terms cancel `fSneakBaseValue`. Closed form:
    /// `max * (1 - needed^(1/exponent))`, with `needed = -base / (sound + skill)`.
    /// Zero when even a touching target is too quiet. Shown as a readout only.
    public static func noiseRadius(
        gait: LocomotionGait?,
        settings: DetectionSettings,
        isExterior: Bool,
        hasLineOfSight: Bool = true,
        traits: DetectionTargetTraits = .neutral,
        noticerSkill: Float = DetectionTargetTraits.startingSkill
    ) -> Float {
        let inputs = DetectionInputs(
            distance: 0,
            hasLineOfSight: hasLineOfSight,
            isInViewCone: false,
            isExterior: isExterior,
            gait: gait,
            traits: traits,
            noticerSkill: noticerSkill
        )
        let noticer = skillFactor(level: noticerSkill, settings: settings)
        let sneaker = skillFactor(level: traits.sneakSkill, settings: settings)
        let audible = soundFactor(inputs: inputs, settings: settings) + noticer
        let deficit = -settings.sneakBaseValue.value - (noticer - sneaker)
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
