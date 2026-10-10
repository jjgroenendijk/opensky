// The detection formula as arithmetic: distance falloff, the three terms, the
// gait table, and noise radius. Values come from the formula in
// `DetectionFormula`, not from recorded output.

@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyPhysics
import Testing

struct DetectionFormulaTests {
    private let settings = DetectionSettings.synthetic

    // MARK: - Settings provenance

    @Test func vanillaSettingsCarryTheInstallValuesAndOpenSkyConstantsSayTheyAreOurs() {
        #expect(settings.sneakBaseValue.value == -15)
        #expect(settings.maxDistance.value == 2500)
        #expect(settings.exteriorDistanceMult.value == 2.1)
        #expect(settings.soundLosMult.value == 0.3)
        #expect(settings.runningMult.value == 2)
        // Every OpenSky constant says so in its own source string, which is the
        // whole point of keeping the two kinds of number apart.
        let ours = settings.report.filter { $0.setting.source == "OpenSky constant" }
        #expect(ours.map(\.editorID) == [
            "distanceAttenuationExponent", "equippedWeightBase", "equippedWeightMult",
            "sneakMovementMult", "sprintMovementMult", "viewConeHalfAngleDegrees",
            "visualBaseValue", "sneakVisualMult", "normalActionSound", "loudActionSound",
            "veryLoudActionSound", "fullLightLuminance", "fullDetectionValue", "gainPerSecond",
            "decayPerSecond", "suspiciousLevel", "detectedLevel"
        ])
        #expect(settings.silentActionSound.value == 10)
        // The synthetic set labels the load-order half as synthetic rather than
        // claiming it came from a plugin nothing loaded.
        #expect(settings.sneakBaseValue.source == "OpenSky synthetic")
    }

    // MARK: - Attenuation

    @Test func attenuationIsTheSquaredLinearFalloffAndIsZeroPastTheRange() {
        // Interior: the range is fSneakMaxDistance itself.
        #expect(DetectionFormula.attenuation(
            distance: 0, settings: settings, isExterior: false
        ) == 1)
        // Half the range squares to a quarter.
        #expect(DetectionFormula.attenuation(
            distance: 1250, settings: settings, isExterior: false
        ) == 0.25)
        #expect(DetectionFormula.attenuation(
            distance: 2500, settings: settings, isExterior: false
        ) == 0)
        #expect(DetectionFormula.attenuation(
            distance: 9999, settings: settings, isExterior: false
        ) == 0)
        // Outdoors the same distance attenuates less, because the range is
        // multiplied by fSneakExteriorDistanceMult.
        #expect(DetectionFormula.maximumDistance(settings: settings, isExterior: true) == 5250)
        #expect(DetectionFormula.attenuation(
            distance: 2500, settings: settings, isExterior: true
        ) > 0.2)
        // A NaN distance attenuates to nothing rather than poisoning the value.
        #expect(DetectionFormula.attenuation(
            distance: .nan, settings: settings, isExterior: false
        ) == 0)
    }

    // MARK: - Terms

    @Test func soundTermFollowsTheMovementTimesWeightShape() {
        // Standing still makes no movement noise at all, and with no action
        // sound the whole term is zero.
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(distance: 0, gait: nil), settings: settings
        ) == 0)
        // Walking, nothing equipped: fSneakEquippedWeightBase alone.
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(distance: 0, gait: .walk), settings: settings
        ) == 12)
        // Equipped weight adds at fSneakEquippedWeightMult per point.
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(
                distance: 0, gait: .walk, traits: DetectionTargetTraits(equippedWeight: 40)
            ),
            settings: settings
        ) == 32)
        // Running doubles it, sprinting trebles it, sneaking cuts it.
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(distance: 0, gait: .run), settings: settings
        ) == 24)
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(distance: 0, gait: .sprint), settings: settings
        ) == 36)
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(distance: 0, gait: .sneak), settings: settings
        ) == 9)
        // Nothing in the way multiplies by 1; a wall multiplies by
        // fSneakSoundLosMult.
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(distance: 0, hasLineOfSight: false, gait: .walk),
            settings: settings
        ) == 12 * 0.3)
    }

    @Test func visualTermNeedsBothASightLineAndTheCone() {
        let seen = DetectionInputs(distance: 0)
        #expect(DetectionFormula.visualFactor(inputs: seen, settings: settings) == 40)
        #expect(DetectionFormula.visualFactor(
            inputs: DetectionInputs(distance: 0, hasLineOfSight: false), settings: settings
        ) == 0)
        #expect(DetectionFormula.visualFactor(
            inputs: DetectionInputs(distance: 0, isInViewCone: false), settings: settings
        ) == 0)
        // Crouching halves the silhouette, which is OpenSky's lever because
        // vanilla spends the Sneak skill instead.
        #expect(DetectionFormula.visualFactor(
            inputs: DetectionInputs(distance: 0, isSneaking: true), settings: settings
        ) == 20)
    }

    @Test func skillTermWeightsTheClampedLevelAndTheGapMovesTheValue() {
        // 15 clamped into 0...100, times fSneakSkillMult.
        #expect(DetectionFormula.skillFactor(settings: settings) == 7.5)
        #expect(DetectionFormula.skillFactor(level: 250, settings: settings) == 50)
        #expect(DetectionFormula.skillFactor(level: .nan, settings: settings) == 7.5)
        func value(noticer: Float, sneaker: Float) -> Float {
            DetectionFormula.breakdown(
                inputs: DetectionInputs(
                    distance: 9999, traits: DetectionTargetTraits(sneakSkill: sneaker),
                    noticerSkill: noticer
                ),
                settings: settings
            ).value
        }
        // Out of range, only the (Noticer - Sneaker) term is left beside the base.
        #expect(value(noticer: 15, sneaker: 15) == -15)
        #expect(value(noticer: 15, sneaker: 75) == -15 + (7.5 - 37.5))
        #expect(value(noticer: 55, sneaker: 15) == -15 + (27.5 - 7.5))
    }

    @Test func muffleSilencesTheArmourButNotTheSteps() {
        func sound(muffle: Float) -> Float {
            DetectionFormula.soundFactor(
                inputs: DetectionInputs(
                    distance: 0, gait: .walk,
                    traits: DetectionTargetTraits(equippedWeight: 40, muffle: muffle)
                ),
                settings: settings
            )
        }
        #expect(sound(muffle: 0) == 32)
        #expect(sound(muffle: 0.5) == 22)
        #expect(sound(muffle: 1) == 12)
        // Stacked muffle past 1 has no extra effect.
        #expect(sound(muffle: 3) == 12)
    }

    @Test func anActionSoundIsHeardEvenWhenStandingStill() {
        let level = settings.actionSound(for: .normal)
        let sound = DetectionFormula.soundFactor(
            inputs: DetectionInputs(
                distance: 0, gait: nil, traits: DetectionTargetTraits(actionSound: level)
            ),
            settings: settings
        )
        #expect(sound == level * 2)
        #expect(settings.actionSound(for: .silent) < settings.actionSound(for: .normal))
        #expect(settings.actionSound(for: .loud) < settings.actionSound(for: .veryLoud))
    }

    @Test func lightAndInvisibilityScaleTheVisualTerm() {
        func visual(_ traits: DetectionTargetTraits) -> Float {
            DetectionFormula.visualFactor(
                inputs: DetectionInputs(distance: 0, traits: traits), settings: settings
            )
        }
        #expect(visual(DetectionTargetTraits(lightLevel: 0.25)) == 10)
        #expect(visual(DetectionTargetTraits(lightLevel: 0)) == 0)
        #expect(visual(DetectionTargetTraits(lightLevel: 4)) == 40)
        #expect(visual(DetectionTargetTraits(isInvisible: true)) == 0)
        // Invisible, but still heard.
        #expect(DetectionFormula.soundFactor(
            inputs: DetectionInputs(
                distance: 0, gait: .walk, traits: DetectionTargetTraits(isInvisible: true)
            ),
            settings: settings
        ) == 12)
    }

    // MARK: - The whole value

    @Test func sneakingLowersTheDetectionValueAgainstTheSameStandingPose() {
        let standing = DetectionFormula.breakdown(
            inputs: DetectionInputs(distance: 500, isExterior: true, gait: .walk),
            settings: settings
        )
        let sneaking = DetectionFormula.breakdown(
            inputs: DetectionInputs(
                distance: 500, isExterior: true, isSneaking: true, gait: .sneak
            ),
            settings: settings
        )
        #expect(standing.isPerceiving)
        #expect(sneaking.isPerceiving)
        #expect(sneaking.value < standing.value)
        // Both terms moved, not just one: crouching is quieter *and* smaller.
        #expect(sneaking.soundFactor < standing.soundFactor)
        #expect(sneaking.visualFactor < standing.visualFactor)
        // Standing in the open at 500 units is well past the full-rate signal,
        // so a standing player is picked up as fast as the model allows.
        #expect(standing.value > settings.fullDetectionValue.value)
    }

    @Test func aBlockedSightLineLeavesOnlyMuffledSoundAndUsuallyNotEnoughOfIt() {
        /// Same wall, same 100 units, same everything except the gait.
        func blocked(_ gait: LocomotionGait) -> DetectionBreakdown {
            DetectionFormula.breakdown(
                inputs: DetectionInputs(
                    distance: 100, hasLineOfSight: false, isExterior: false, gait: gait
                ),
                settings: settings
            )
        }
        #expect(blocked(.walk).visualFactor == 0)
        #expect(!blocked(.walk).isPerceiving)
        // A sprint through the same wall at the same range is loud enough to
        // notice, which is what makes the gait multiplier worth having.
        #expect(blocked(.sprint).isPerceiving)
    }

    // MARK: - Noise radius

    @Test func noiseRadiusOrdersTheGaitsAndIsZeroForSomethingTooQuietToHear() {
        func radius(_ gait: LocomotionGait?) -> Float {
            DetectionFormula.noiseRadius(gait: gait, settings: settings, isExterior: false)
        }
        #expect(radius(nil) == 0)
        #expect(radius(.sneak) > 0)
        #expect(radius(.sneak) < radius(.walk))
        #expect(radius(.walk) < radius(.run))
        #expect(radius(.run) < radius(.sprint))
        // Outdoors every radius grows with the range it attenuates over.
        #expect(DetectionFormula.noiseRadius(
            gait: .walk, settings: settings, isExterior: true
        ) > radius(.walk))
        // Through a wall the same gait carries less far.
        #expect(DetectionFormula.noiseRadius(
            gait: .run, settings: settings, isExterior: false, hasLineOfSight: false
        ) < radius(.run))
    }
}
