// The detection value, as pure arithmetic. The shape is UESP "Skyrim:Sneak",
// "Remaining Undetected", and CK wiki "Category:Detection", with constants from
// `DetectionSettings`. See docs/engine/detection.md.

import Foundation
public import OpenSkyPerceptionInterface
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
    static func attenuation(
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
    static func movementMultiplier(
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
    static func soundFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
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

    /// The visual term before distance attenuation: light, movement, and the observer's
    /// blindness. Zero without a clear sight line, outside the cone, for a sleeping
    /// observer, and for an invisible target. Crouching does not change it.
    static func visualFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        guard
            inputs.hasLineOfSight, inputs.isInViewCone, !inputs.observer.isSleeping,
            !inputs.traits.isInvisible
        else { return 0 }
        return lightFactor(inputs: inputs, settings: settings)
            * movementFactor(inputs: inputs, settings: settings)
            * blindnessFactor(inputs.observer.blindness)
            * finiteNonNegative(inputs.traits.sizeFactor)
    }

    /// `1 + moving * fSneakLightMoveMult + running * fSneakLightRunMult`, with moving
    /// and running as 0 or 1, times the Mod Detection Movement perks. A sprint counts
    /// as running.
    static func movementFactor(
        inputs: DetectionInputs, settings: DetectionSettings
    ) -> Float {
        guard let gait = inputs.gait else { return 1 }
        let isRunning = gait == .run || gait == .sprint
        return max(
            0, 1 + settings.lightMoveMult.value + (isRunning ? settings.lightRunMult.value : 0)
        ) * finiteNonNegative(inputs.traits.movementMultiplier)
    }

    /// `(100 - int(Blindness)) / 100`, so 100 Blindness sees nothing.
    static func blindnessFactor(_ blindness: Float) -> Float {
        let points = blindness.isFinite ? blindness.rounded(.towardZero) : 0
        return min(max((100 - points) / 100, 0), 1)
    }

    /// The target's light level: its 0...1 light times 100, times 3 for an observer
    /// with Night Eye, less the indoor offset, held in 0...`iLightLevelMax`. The offset
    /// is `iLightLevelInteriorMod`, or the cell's ambient light when that is smaller.
    static func lightLevel(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        let cap = inputs.traits.interiorLightCap
        let interior = inputs.isExterior ? 0 : min(
            settings.lightLevelInteriorMod.value, cap.isNaN ? .infinity : max(0, cap)
        )
        let seen = inputs.observer.hasNightEye ? nightEyeLightFactor : 1
        let level = finiteNonNegative(inputs.traits.lightLevel) * 100 * seen - interior
        return min(max(0, level), max(0, settings.lightLevelMax.value)).rounded()
    }

    static let nightEyeLightFactor: Float = 3

    /// `light level * multiplier + fDetectionSneakLightMod`. The multiplier is
    /// `fSneakLightMult` indoors and `fSneakLightExteriorMult` outdoors.
    static func lightFactor(inputs: DetectionInputs, settings: DetectionSettings) -> Float {
        let multiplier = inputs.isExterior ? settings.lightExteriorMult.value
            : settings.lightMult.value
        return max(
            0, lightLevel(inputs: inputs, settings: settings) * multiplier + settings.lightMod.value
        )
    }

    /// The observer's Sneak skill mapped onto `fSneakPerceptionSkillMin...Max`, a line
    /// through both ends and not a clamp.
    static func perception(_ level: Float, settings: DetectionSettings) -> Float {
        let level = level.isFinite ? level : DetectionTargetTraits.startingSkill
        let low = settings.perceptionSkillMin.value
        return low + (settings.perceptionSkillMax.value - low) * level / 100
    }

    /// The observer's skill, times `1 + alert * fSneakAlertMod + sleeping *
    /// fSneakSleepMod + fightingAnother * fSneakCombatMod`, times `fSneakSkillMult`.
    static func noticerFactor(
        inputs: DetectionInputs,
        settings: DetectionSettings
    ) -> Float {
        let state = inputs.observer
        let mod = 1 + (state.isAlert ? settings.alertMod.value : 0)
            + (state.isSleeping ? settings.sleepMod.value : 0)
            + (state.isFightingAnother ? settings.combatMod.value : 0)
        return perception(inputs.noticerSkill, settings: settings) * mod
            * settings.skillMult.value
    }

    /// The target's skill term: zero unless it sneaks. The player's skill is first
    /// `fPlayerDetectionSneakBase + fPlayerDetectionSneakMult * skill`.
    static func sneakerFactor(
        inputs: DetectionInputs,
        settings: DetectionSettings
    ) -> Float {
        guard inputs.isSneaking else { return 0 }
        if let effective = inputs.traits.effectiveSneakSkill, effective.isFinite {
            return effective * settings.skillMult.value
        }
        let raw = inputs.traits.sneakSkill
        let skill = raw.isFinite ? raw : DetectionTargetTraits.startingSkill
        let effective = inputs.isPlayerTarget
            ? settings.playerSneakBase.value + settings.playerSneakMult.value * skill
            : skill
        return effective * settings.skillMult.value
    }

    /// A value between 0 and 1 counts as 1, any other loses its fraction, and a plain 0
    /// becomes -1: sight never gives exactly 0.
    static func rounded(_ value: Float) -> Float {
        guard value.isFinite else { return -1 }
        if value > 0, value < 1 {
            return 1
        }
        let whole = value.rounded(.towardZero)
        return whole == 0 ? -1 : whole
    }

    private static func finiteNonNegative(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    /// The whole formula, with its terms. Past the maximum distance the formula does
    /// not run, and the value is `fSneakBaseValue` alone.
    static func breakdown(
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
        let asleep = inputs.observer.isSleeping ? max(0, 1 + settings.sleepBonus.value) : 1
        let value = settings.sneakBaseValue.value
            + (sound * asleep + visual) * attenuation
            + noticerFactor(inputs: inputs, settings: settings) * attenuation
            - sneakerFactor(inputs: inputs, settings: settings)
        return DetectionBreakdown(
            soundFactor: sound, visualFactor: visual, value: rounded(value)
        )
    }

    /// How far a target moving at `gait` can be heard, in world units: where the
    /// sound and observer skill terms cancel `fSneakBaseValue` and the sneaker's skill.
    /// Closed form: `max * (1 - needed^(1/exponent))`.
    /// Zero when even a touching target is too quiet. Shown as a readout only.
    static func noiseRadius(
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
            isSneaking: gait == .sneak,
            gait: gait,
            traits: traits,
            noticerSkill: noticerSkill
        )
        let noticer = noticerFactor(inputs: inputs, settings: settings)
        let audible = soundFactor(inputs: inputs, settings: settings) + noticer
        let deficit = -settings.sneakBaseValue.value
            + sneakerFactor(inputs: inputs, settings: settings)
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
