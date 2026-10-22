// The detection value, as pure arithmetic. The shape is UESP "Skyrim:Sneak",
// "Remaining Undetected", and CK wiki "Category:Detection", with constants from
// `DetectionSettings`. See docs/engine/detection.md.

import Foundation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd

nonisolated public enum DetectionFormula: Sendable {
    /// The range this pair's senses attenuate over, world units.
    public static func maximumDistance(
        settings: DetectionSettings, isExterior: Bool, isFlying: Bool = false
    ) -> Float {
        var range = max(0, settings.maxDistance.value)
        if isExterior {
            range *= max(0, settings.exteriorDistanceMult.value)
        }
        if isFlying {
            range *= max(0, settings.flyingDistanceMult.value)
        }
        return range
    }

    /// Whether `distance` is short enough for either sense to reach.
    public static func isInRange(
        distance: Float,
        settings: DetectionSettings,
        isExterior: Bool,
        isFlying: Bool = false
    ) -> Bool {
        distance.isFinite && distance >= 0
            && distance < maximumDistance(
                settings: settings, isExterior: isExterior, isFlying: isFlying
            )
    }

    /// `((max - distance) / max) ^ exponent`, clamped to 0...1.
    ///
    /// Zero at and beyond the maximum distance, and 1 at zero distance. A
    /// non-finite or negative distance attenuates to nothing rather than
    /// producing a NaN that would poison every comparison downstream.
    public static func attenuation(
        distance: Float,
        settings: DetectionSettings,
        isExterior: Bool,
        isFlying: Bool = false
    ) -> Float {
        guard
            isInRange(
                distance: distance, settings: settings, isExterior: isExterior,
                isFlying: isFlying
            )
        else {
            return 0
        }
        let maximum = maximumDistance(
            settings: settings, isExterior: isExterior, isFlying: isFlying
        )
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
            * finiteNonNegative(traits.movementMultiplier)
        let action = finiteNonNegative(traits.actionSound) * settings.actionMult.value
        let occlusion = inputs.hasLineOfSight ? 1 : max(0, settings.soundLosMult.value)
        return settings.soundsMult.value * (movement + action) * occlusion
    }

    /// The CK wiki's visual term before distance attenuation: light, movement, the
    /// observer's blindness, and invisibility. Zero without a clear sight line, outside
    /// the cone, or for a sleeping observer, whose blindness the CK wiki sets to full.
    public static func visualFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        guard inputs.hasLineOfSight, inputs.isInViewCone, !inputs.observer.isSleeping else {
            return 0
        }
        let crouch = inputs.isSneaking ? max(0, settings.sneakVisualMult.value) : 1
        let invisibility = inputs.traits.isInvisible ? max(0, settings.stealthBoyMult.value) : 1
        return lightFactor(inputs: inputs, settings: settings)
            * movementFactor(inputs: inputs, settings: settings)
            * blindnessFactor(inputs.observer.blindness)
            * invisibility * crouch
    }

    /// `1 + moving * fSneakLightMoveMult + running * fSneakLightRunMult`, with moving
    /// and running as 0 or 1. A sprint counts as running.
    public static func movementFactor(
        inputs: DetectionInputs, settings: DetectionSettings
    ) -> Float {
        guard let gait = inputs.gait else { return 1 }
        let isRunning = gait == .run || gait == .sprint
        return max(
            0, 1 + settings.lightMoveMult.value + (isRunning ? settings.lightRunMult.value : 0)
        )
    }

    /// `(100 - int(Blindness)) / 100`, so 100 Blindness sees nothing.
    static func blindnessFactor(_ blindness: Float) -> Float {
        let points = blindness.isFinite ? blindness.rounded(.towardZero) : 0
        return min(max((100 - points) / 100, 0), 1)
    }

    /// `GetLightLevel` of the target: its 0...1 light times 100, plus
    /// `iLightLevelInteriorMod` indoors, capped at `iLightLevelMax`.
    public static func lightLevel(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        let interior = inputs.isExterior ? 0 : settings.lightLevelInteriorMod.value
        let level = finiteNonNegative(inputs.traits.lightLevel) * 100 + interior
        return min(max(0, level), max(0, settings.lightLevelMax.value))
    }

    /// The CK wiki's light term, `(fDetectionSneakLightMod + light level) * fSneakLightMult`,
    /// halved outdoors by `fSneakLightExteriorMult`.
    public static func lightFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        let exterior = inputs.isExterior ? max(0, settings.lightExteriorMult.value) : 1
        let light = (settings.lightMod.value + lightLevel(inputs: inputs, settings: settings))
            * settings.lightMult.value * exterior
        return max(0, light)
    }

    /// One skill level, clamped and weighted into a skill factor.
    public static func skillFactor(
        level: Float = DetectionTargetTraits.startingSkill,
        settings: DetectionSettings
    ) -> Float {
        clampedSkill(level, settings: settings) * settings.skillMult.value
    }

    /// A skill level clamped to `fSneakPerceptionSkillMin...Max`.
    static func clampedSkill(_ level: Float, settings: DetectionSettings) -> Float {
        let level = level.isFinite ? level : DetectionTargetTraits.startingSkill
        return min(
            max(level, settings.perceptionSkillMin.value),
            settings.perceptionSkillMax.value
        )
    }

    /// The observer's skill factor, times `1 + alert * fSneakAlertMod + sleeping *
    /// fSneakSleepBonus + notCombatTarget * fSneakCombatMod` (CK wiki "Category:Detection").
    public static func noticerFactor(
        inputs: DetectionInputs,
        settings: DetectionSettings
    ) -> Float {
        let state = inputs.observer
        let mod = 1 + (state.isAlert ? settings.alertMod.value : 0)
            + (state.isSleeping ? settings.sleepBonus.value : 0)
            + (state.isFightingAnother ? settings.combatMod.value : 0)
        return skillFactor(level: inputs.noticerSkill, settings: settings) * max(0, mod)
    }

    /// The target's skill factor. The player's is `fPlayerDetectionSneakBase +
    /// fPlayerDetectionSneakMult * skill`, with the skill clamped as for any actor.
    public static func sneakerFactor(
        inputs: DetectionInputs,
        settings: DetectionSettings
    ) -> Float {
        guard inputs.isPlayerTarget else {
            return skillFactor(level: inputs.traits.sneakSkill, settings: settings)
        }
        let skill = clampedSkill(inputs.traits.sneakSkill, settings: settings)
        return settings.playerSneakBase.value + settings.playerSneakMult.value * skill
    }

    private static func finiteNonNegative(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    /// The whole formula, with its terms. Past the maximum distance the value is
    /// `fSneakBaseValue` alone: the unattenuated skill gap must not let a skilled
    /// observer notice a target at any range.
    public static func breakdown(
        inputs: DetectionInputs,
        settings: DetectionSettings
    ) -> DetectionBreakdown {
        let isFlying = inputs.observer.isFlying
        let attenuation = attenuation(
            distance: inputs.distance, settings: settings, isExterior: inputs.isExterior,
            isFlying: isFlying
        )
        let sound = soundFactor(inputs: inputs, settings: settings)
        let visual = visualFactor(inputs: inputs, settings: settings)
        guard
            isInRange(
                distance: inputs.distance,
                settings: settings,
                isExterior: inputs.isExterior,
                isFlying: isFlying
            )
        else {
            return DetectionBreakdown(
                soundFactor: sound, visualFactor: visual, value: settings.sneakBaseValue.value
            )
        }
        let noticer = noticerFactor(inputs: inputs, settings: settings)
        let sneaker = sneakerFactor(inputs: inputs, settings: settings)
        var value = settings.sneakBaseValue.value
            + (sound + visual + noticer) * attenuation
            + (noticer - sneaker)
            + (inputs.observer.isSleeping ? settings.sleepMod.value : 0)
        if inputs.isPlayerTarget {
            value = max(value, settings.playerDetectFloor.value)
        }
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
