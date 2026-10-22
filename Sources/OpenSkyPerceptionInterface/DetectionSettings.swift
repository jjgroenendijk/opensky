// The numbers detection resolves its formula from, resolved once at setup, each
// naming its source. GMSTs come from the load order, with install-observed
// fallbacks (UESP's `fSneakDistanceAttenuationExponent` does not exist). Values
// no record documents, such as the view cone, are marked "OpenSky constant".
// See docs/engine/detection.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

nonisolated public struct DetectionSettings: Equatable, Sendable {
    // MARK: - Read from the load order

    /// `fSneakBaseValue` — the constant every detection value starts from. It
    /// is negative, which is what makes a distant, silent, unseen target
    /// undetected rather than marginally detected.
    public var sneakBaseValue: MovementSetting
    /// `fSneakMaxDistance` — the range past which sight and hearing both
    /// attenuate to nothing, world units.
    public var maxDistance: MovementSetting
    /// `fSneakExteriorDistanceMult` — what that range is multiplied by outdoors,
    /// where there are no walls to stop either sense.
    public var exteriorDistanceMult: MovementSetting
    /// `fSneakSoundsMult` — what the whole sound term is multiplied by.
    public var soundsMult: MovementSetting
    /// `fSneakSoundLosMult` — what the sound term is multiplied by when nothing
    /// can see through to the target. Sound reaches around a corner; it just
    /// reaches less.
    public var soundLosMult: MovementSetting
    /// `fSneakRunningMult` — how much louder a running target is than a walking
    /// one.
    public var runningMult: MovementSetting
    /// `fSneakActionMult` — what an action sound is multiplied by.
    public var actionMult: MovementSetting
    /// `fSneakSkillMult` — what a skill level is multiplied by to become a skill
    /// factor.
    public var skillMult: MovementSetting
    /// `fSneakPerceptionSkillMin` and `fSneakPerceptionSkillMax` — the range a
    /// skill level is clamped to before it is weighted.
    public var perceptionSkillMin: MovementSetting
    public var perceptionSkillMax: MovementSetting
    /// `iSoundLevelSilent` — the action sound of a silent weapon or spell.
    public var silentActionSound: MovementSetting
    /// `fSkillUsageSneakPerSecond` — Sneak skill uses per second spent hidden
    /// near an observer.
    public var skillUsePerSecond: MovementSetting
    /// `fSneakLightMult`, `fSneakLightExteriorMult`, and `fDetectionSneakLightMod`: the
    /// light term is `(mod + light level) * mult`, times the exterior mult outdoors.
    public var lightMult: MovementSetting
    public var lightExteriorMult: MovementSetting
    public var lightMod: MovementSetting
    /// `iLightLevelInteriorMod` is added to an interior light level, and `iLightLevelMax`
    /// caps it (CK wiki "Perk Entry Point", Mod Detection Light).
    public var lightLevelInteriorMod: MovementSetting
    public var lightLevelMax: MovementSetting
    /// `fSneakAlertMod` and `fSneakSleepBonus` weight the noticer skill factor of an
    /// alert or a sleeping observer (CK wiki "Category:Detection").
    public var alertMod: MovementSetting
    public var sleepBonus: MovementSetting
    /// `fSneakSleepMod`, added to a sleeping observer's detection value.
    public var sleepMod: MovementSetting
    /// `fPlayerDetectionSneakBase` and `fPlayerDetectionSneakMult` make the player's
    /// sneaker skill factor; `fPlayerDetectActorValue` is the lowest value against it.
    public var playerSneakBase: MovementSetting
    public var playerSneakMult: MovementSetting
    public var playerDetectFloor: MovementSetting
    /// `fSneakFlyingDistanceMult`: what a flying observer's range is multiplied by.
    public var flyingDistanceMult: MovementSetting
    /// `fSneakLightMoveMult` and `fSneakLightRunMult`: a moving or running target is
    /// easier to see, `1 + moving * move + running * run` (CK wiki "Category:Detection").
    public var lightMoveMult: MovementSetting
    public var lightRunMult: MovementSetting
    /// `fSneakStealthBoyMult`: the visual term of an invisible target is multiplied by it.
    public var stealthBoyMult: MovementSetting
    /// `fSneakCombatMod`: weights the skill of an observer that fights someone else.
    public var combatMod: MovementSetting

    // MARK: - OpenSky's own

    /// The exponent the distance attenuation is raised to. UESP names an
    /// `fSneakDistanceAttenuationExponent` of 2; no GMST of that editor ID
    /// exists on the install, so the exponent is ours and says so.
    public var distanceAttenuationExponent: MovementSetting
    /// The `fSneakEquippedWeightBase` term of the movement-noise formula — what
    /// a target counts as wearing before anything is equipped. UESP names it as
    /// a setting; the install carries no GMST by that editor ID.
    public var equippedWeightBase: MovementSetting
    /// The `fSneakEquippedWeightMult` term, noise per point of equipped weight,
    /// on the same terms.
    public var equippedWeightMult: MovementSetting
    /// What movement noise is multiplied by while the target is sneaking.
    /// Vanilla's movement term has no crouch factor, but the sneak walk is
    /// slower and softer than a walk, so it is quieter here too.
    public var sneakMovementMult: MovementSetting
    /// The same for a sprinting target, one step above `fSneakRunningMult`.
    public var sprintMovementMult: MovementSetting
    /// Half-angle of an observer's view cone, degrees off its facing. 90 makes
    /// the cone a forward hemisphere: a target directly beside an observer is on
    /// the edge of sight and one behind it is not seen at all.
    public var viewConeHalfAngleDegrees: MovementSetting
    /// What the visual term is multiplied by while the target is sneaking.
    public var sneakVisualMult: MovementSetting
    /// The action sounds of the other three sound levels. The install has a
    /// game setting only for the silent level.
    public var normalActionSound: MovementSetting
    public var loudActionSound: MovementSetting
    public var veryLoudActionSound: MovementSetting
    /// The luminance of the light that reads as light level 100, a lit day outdoors
    /// (CK wiki "GetLightLevel").
    public var fullLightLuminance: MovementSetting
    /// Detection value at which the level climbs at its full rate. A stronger
    /// signal than this does not climb faster.
    public var fullDetectionValue: MovementSetting
    /// Detection level gained per second at a full-rate signal, out of 100.
    public var gainPerSecond: MovementSetting
    /// Detection level lost per second while nothing is perceived.
    public var decayPerSecond: MovementSetting
    /// Level at or above which an observer is suspicious and has somewhere to
    /// investigate.
    public var suspiciousLevel: MovementSetting
    /// Level at which an observer has detected the target outright. The top of
    /// the scale, so "detected" and "certain" are the same state.
    public var detectedLevel: MovementSetting
    /// How near an observer must be for hiding to train Sneak. UESP: "within
    /// ~45 feet", about 960 units.
    public var skillUseRange: MovementSetting

    /// Values for synthetic scenes and tests: the numbers the install carries
    /// plus OpenSky's own, stated explicitly so a test never depends on an
    /// install being present.
    public static let synthetic = make(loadOrderSource: "OpenSky synthetic") { _ in nil }

    /// Reads every load-order setting out of `store`, falling back to the value
    /// observed in vanilla `Skyrim.esm` and saying so when the load order
    /// carries none. OpenSky's own constants are the same either way, because no
    /// plugin authors them.
    public static func resolve(store: GameSettingStore) -> DetectionSettings {
        make(loadOrderSource: "vanilla Skyrim.esm value") { editorID in
            guard let resolved = store.setting(editorID: editorID) else { return nil }
            let value: Float
            switch resolved.setting.value {
            case let .float(number): value = number
            case let .integer(number): value = Float(number)
            default: return nil
            }
            guard value.isFinite else { return nil }
            return MovementSetting(value: value, source: resolved.sourcePlugin)
        }
    }

    /// The action sound of one sound level.
    public func actionSound(for level: DetectionSoundLevel) -> Float {
        switch level {
        case .silent: max(0, silentActionSound.value)
        case .normal: max(0, normalActionSound.value)
        case .loud: max(0, loudActionSound.value)
        case .veryLoud: max(0, veryLoudActionSound.value)
        }
    }

    /// The cosine the view-cone test compares a facing dot against, computed
    /// once here rather than per pair per step.
    public var viewConeCosine: Float {
        cosf(min(max(viewConeHalfAngleDegrees.value, 0), 180) * .pi / 180)
    }

    // MARK: - Private

    /// One constant of ours, labelled as ours wherever it is reported.
    private static func ours(_ value: Float) -> MovementSetting {
        MovementSetting(value: value, source: "OpenSky constant")
    }

    /// Builds a whole set: `override` supplies a load-order value where one exists,
    /// and the rest fall back to vanilla numbers under `loadOrderSource`. One builder,
    /// so the synthetic and resolved sets cannot drift apart.
    private static func make(
        loadOrderSource: String,
        override: (String) -> MovementSetting?
    ) -> DetectionSettings {
        func vanilla(_ editorID: String, _ fallback: Float) -> MovementSetting {
            override(editorID) ?? MovementSetting(value: fallback, source: loadOrderSource)
        }
        // A setting `Skyrim.esm` does not override, so the engine default applies.
        func engineDefault(_ editorID: String, _ fallback: Float) -> MovementSetting {
            override(editorID) ?? MovementSetting(value: fallback, source: "CK wiki default")
        }
        return DetectionSettings(
            sneakBaseValue: vanilla("fSneakBaseValue", -15),
            maxDistance: vanilla("fSneakMaxDistance", 2500),
            exteriorDistanceMult: vanilla("fSneakExteriorDistanceMult", 2.1),
            soundsMult: vanilla("fSneakSoundsMult", 1),
            soundLosMult: vanilla("fSneakSoundLosMult", 0.3),
            runningMult: vanilla("fSneakRunningMult", 2),
            actionMult: vanilla("fSneakActionMult", 2),
            skillMult: vanilla("fSneakSkillMult", 0.5),
            perceptionSkillMin: vanilla("fSneakPerceptionSkillMin", 0),
            perceptionSkillMax: vanilla("fSneakPerceptionSkillMax", 100),
            silentActionSound: vanilla("iSoundLevelSilent", 10),
            skillUsePerSecond: vanilla("fSkillUsageSneakPerSecond", 0.625),
            lightMult: vanilla("fSneakLightMult", 0.33),
            lightExteriorMult: vanilla("fSneakLightExteriorMult", 0.5),
            lightMod: vanilla("fDetectionSneakLightMod", 15),
            lightLevelInteriorMod: vanilla("iLightLevelInteriorMod", 25),
            lightLevelMax: vanilla("iLightLevelMax", 300),
            alertMod: vanilla("fSneakAlertMod", 0),
            sleepBonus: vanilla("fSneakSleepBonus", 0),
            sleepMod: vanilla("fSneakSleepMod", 0),
            playerSneakBase: vanilla("fPlayerDetectionSneakBase", 10),
            playerSneakMult: vanilla("fPlayerDetectionSneakMult", 0.4),
            playerDetectFloor: vanilla("fPlayerDetectActorValue", -30),
            flyingDistanceMult: vanilla("fSneakFlyingDistanceMult", 3),
            lightMoveMult: engineDefault("fSneakLightMoveMult", 0.01),
            lightRunMult: engineDefault("fSneakLightRunMult", 0.2),
            stealthBoyMult: engineDefault("fSneakStealthBoyMult", 0),
            combatMod: engineDefault("fSneakCombatMod", -0.4),
            distanceAttenuationExponent: ours(2),
            equippedWeightBase: ours(12),
            equippedWeightMult: ours(0.5),
            sneakMovementMult: ours(0.75),
            sprintMovementMult: ours(3),
            viewConeHalfAngleDegrees: ours(90),
            sneakVisualMult: ours(0.5),
            normalActionSound: ours(25),
            loudActionSound: ours(50),
            veryLoudActionSound: ours(100),
            fullLightLuminance: ours(1),
            fullDetectionValue: ours(25),
            gainPerSecond: ours(100),
            decayPerSecond: ours(20),
            suspiciousLevel: ours(25),
            detectedLevel: ours(100),
            skillUseRange: ours(960)
        )
    }
}

/// The sound level a weapon (`WEAP` `VNAM`) or a magic effect (`MGEF` casting
/// sound level) declares. The raw values are the record values.
nonisolated public enum DetectionSoundLevel: UInt32, CaseIterable, Sendable {
    case loud = 0
    case normal = 1
    case silent = 2
    case veryLoud = 3
}
