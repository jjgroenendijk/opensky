// The sound event an observer checks when it sees nothing of a target: how long one
// lasts, how far it reaches, and its sound-only detection value.
// See docs/engine/detection-events.md.

import Foundation
import OpenSkyPerceptionInterface
import OpenSkyPhysics

/// What one observer perceives of an event's place.
nonisolated struct DetectionEventSight: Equatable, Sendable {
    var distance: Float
    var hasLineOfSight: Bool
    var isInViewCone: Bool
}

nonisolated public enum DetectionEventRule: Sendable {
    /// `fDetectionEventExpireTime`.
    public static let expireSeconds: Float = 5
    static let playerHearingDistance: Float = 1536
    static let actorHearingDistance: Float = 512
    /// From this level a sound is very loud: twice the distance, and its own range.
    static let veryLoudLevel: Float = 200
    static let veryLoudRange: Float = 3072
    /// The light level the sound-only formula uses when the event's place is in view.
    static let interiorLightLevel: Float = 225
    static let exteriorLightLevel: Float = 75

    /// How far from an event an observer still checks it.
    public static func hearingDistance(level: Float, isPlayerSound: Bool) -> Float {
        let distance = isPlayerSound ? playerHearingDistance : actorHearingDistance
        return level >= veryLoudLevel ? distance * 2 : distance
    }

    /// The sound-only form of the formula. The pair's `inputs` give the observer, the
    /// skills, and indoors or outdoors; `sight` gives the event's place.
    static func value(
        of event: DetectionSoundEvent, sight: DetectionEventSight,
        inputs: DetectionInputs, settings: DetectionSettings
    ) -> Float {
        let range = event.level >= veryLoudLevel
            ? veryLoudRange
            : DetectionFormula.maximumDistance(
                settings: settings, isExterior: inputs.isExterior,
                isFlying: inputs.observer.isFlying
            )
        guard sight.distance.isFinite, sight.distance >= 0, sight.distance < range else {
            return settings.sneakBaseValue.value
        }
        let attenuation = powf(
            (range - sight.distance) / range, max(0, settings.distanceAttenuationExponent.value)
        )
        let occlusion = sight.hasLineOfSight ? 1 : max(0, settings.soundLosMult.value)
        let sound = settings.soundsMult.value * max(0, event.level) * settings.actionMult.value
            * occlusion
        let asleep = inputs.observer.isSleeping ? max(0, 1 + settings.sleepBonus.value) : 1
        let total = settings.sneakBaseValue.value
            + (sound * asleep + visual(sight: sight, inputs: inputs, settings: settings))
            * attenuation
            + DetectionFormula.noticerFactor(inputs: inputs, settings: settings) * attenuation
            - DetectionFormula.sneakerFactor(inputs: inputs, settings: settings)
        return DetectionFormula.rounded(total)
    }

    /// Sight of the event's place at a fixed light level. Zero when the place is not in
    /// view and for a sleeping observer.
    private static func visual(
        sight: DetectionEventSight, inputs: DetectionInputs, settings: DetectionSettings
    ) -> Float {
        guard sight.hasLineOfSight, sight.isInViewCone, !inputs.observer.isSleeping else {
            return 0
        }
        let level = inputs.isExterior ? exteriorLightLevel : interiorLightLevel
        let multiplier = inputs.isExterior ? settings.lightExteriorMult.value
            : settings.lightMult.value
        return max(0, level * multiplier + settings.lightMod.value)
            * DetectionFormula.blindnessFactor(inputs.observer.blindness)
    }
}
