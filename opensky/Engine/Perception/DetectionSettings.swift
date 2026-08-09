// The numbers detection resolves its formula from (issue #202, roadmap item
// 16.6), in the shape `CombatSettings` and `ArcherySettings` established:
// immutable, resolved once at setup, every value carrying the name of where it
// came from so a readout can say "this is Skyrim.esm's number" rather than
// presenting an OpenSky constant as the same kind of fact.
//
// ## Two kinds of number, kept apart on purpose
//
// The first kind is a GMST the shipped game carries. UESP "Skyrim:Sneak" writes
// the detection formula in terms of named settings, and the ten the local
// install actually holds are read out of the load order here, exactly as the
// block factors are. Their fallbacks are the values observed on the install
// (2026-08-09, `openskycli gmst list --prefix fsneak`), not the values a wiki
// prints — which matters at least once already: UESP names an
// `fSneakDistanceAttenuationExponent`, and no GMST of that editor ID exists.
//
// The second kind is a number vanilla keeps in AI internals that no record
// documents. There is no GMST for a view cone, for how loud a crouching target
// is, for how fast an alerted guard makes up its mind, or for how long it takes
// to forget. Those are OpenSky's own, they carry the source string "OpenSky
// constant" wherever they are reported, and the docs page states them as ours.
// That is the same honesty rule `DevTargetDriver` follows: an invented number
// that reads like a measured one is worse than no number at all.
//
// A third category is deliberately not resolved here at all: inputs the engine
// cannot supply yet. Light level, muffle, action sounds and the Sneak skill are
// pinned at documented neutral values in `DetectionFormula` and listed as gaps
// on the docs page. None of them is approximated. The install does carry the
// settings a light term would read — `fSneakLightMult`,
// `fSneakLightExteriorMult` and `fDetectionSneakLightMod` — and they are
// deliberately left unresolved until there is a light level to multiply.
//
// Documented in docs/engine/detection.md.

import Foundation

nonisolated struct DetectionSettings: Equatable {
    // MARK: - Read from the load order

    /// `fSneakBaseValue` — the constant every detection value starts from. It
    /// is negative, which is what makes a distant, silent, unseen target
    /// undetected rather than marginally detected.
    let sneakBaseValue: MovementSetting
    /// `fSneakMaxDistance` — the range past which sight and hearing both
    /// attenuate to nothing, world units.
    let maxDistance: MovementSetting
    /// `fSneakExteriorDistanceMult` — what that range is multiplied by outdoors,
    /// where there are no walls to stop either sense.
    let exteriorDistanceMult: MovementSetting
    /// `fSneakSoundsMult` — what the whole sound term is multiplied by.
    let soundsMult: MovementSetting
    /// `fSneakSoundLosMult` — what the sound term is multiplied by when nothing
    /// can see through to the target. Sound reaches around a corner; it just
    /// reaches less.
    let soundLosMult: MovementSetting
    /// `fSneakRunningMult` — how much louder a running target is than a walking
    /// one.
    let runningMult: MovementSetting
    /// `fSneakActionMult` — what an action sound is multiplied by. OpenSky feeds
    /// no action sounds yet, so this multiplies a pinned zero; it is resolved
    /// anyway so the term is wired rather than absent.
    let actionMult: MovementSetting
    /// `fSneakSkillMult` — what a skill level is multiplied by to become a skill
    /// factor. Both skills are pinned (see `DetectionFormula`), so this weights
    /// a documented constant rather than a stored actor value.
    let skillMult: MovementSetting
    /// `fSneakPerceptionSkillMin` and `fSneakPerceptionSkillMax` — the range a
    /// skill level is clamped to before it is weighted.
    let perceptionSkillMin: MovementSetting
    let perceptionSkillMax: MovementSetting

    // MARK: - OpenSky's own

    /// The exponent the distance attenuation is raised to. UESP names an
    /// `fSneakDistanceAttenuationExponent` of 2; no GMST of that editor ID
    /// exists on the install, so the exponent is ours and says so.
    let distanceAttenuationExponent: MovementSetting
    /// The `fSneakEquippedWeightBase` term of the movement-noise formula — what
    /// a target counts as wearing before anything is equipped. UESP names it as
    /// a setting; the install carries no GMST by that editor ID.
    let equippedWeightBase: MovementSetting
    /// The `fSneakEquippedWeightMult` term, noise per point of equipped weight,
    /// on the same terms.
    let equippedWeightMult: MovementSetting
    /// What movement noise is multiplied by while the target is sneaking.
    /// Vanilla's own movement term has no crouch factor at all — it spends the
    /// Sneak skill on the observer's side of the formula instead — and OpenSky
    /// has no skills to spend, so the gait is where sneaking has to pay.
    let sneakMovementMult: MovementSetting
    /// The same for a sprinting target, one step above `fSneakRunningMult`.
    let sprintMovementMult: MovementSetting
    /// Half-angle of an observer's view cone, degrees off its facing. 90 makes
    /// the cone a forward hemisphere: a target directly beside an observer is on
    /// the edge of sight and one behind it is not seen at all.
    let viewConeHalfAngleDegrees: MovementSetting
    /// The visual term a lit, upright target in plain sight contributes. Scaled
    /// to sit alongside the sound term, whose vanilla base is 12.
    let visualBaseValue: MovementSetting
    /// What the visual term is multiplied by while the target is sneaking.
    let sneakVisualMult: MovementSetting
    /// Detection value at which the level climbs at its full rate. A stronger
    /// signal than this does not climb faster.
    let fullDetectionValue: MovementSetting
    /// Detection level gained per second at a full-rate signal, out of 100.
    let gainPerSecond: MovementSetting
    /// Detection level lost per second while nothing is perceived.
    let decayPerSecond: MovementSetting
    /// Level at or above which an observer is suspicious and has somewhere to
    /// investigate.
    let suspiciousLevel: MovementSetting
    /// Level at which an observer has detected the target outright. The top of
    /// the scale, so "detected" and "certain" are the same state.
    let detectedLevel: MovementSetting

    /// Values for synthetic scenes and tests: the numbers the install carries
    /// plus OpenSky's own, stated explicitly so a test never depends on an
    /// install being present.
    static let synthetic = make(loadOrderSource: "OpenSky synthetic") { _ in nil }

    /// Reads every load-order setting out of `store`, falling back to the value
    /// observed in vanilla `Skyrim.esm` and saying so when the load order
    /// carries none. OpenSky's own constants are the same either way, because no
    /// plugin authors them.
    static func resolve(store: GameSettingStore) -> DetectionSettings {
        make(loadOrderSource: "vanilla Skyrim.esm value") { editorID in
            guard
                let resolved = store.setting(editorID: editorID),
                case let .float(value) = resolved.setting.value,
                value.isFinite
            else { return nil }
            return MovementSetting(value: value, source: resolved.sourcePlugin)
        }
    }

    /// The cosine the view-cone test compares a facing dot against, computed
    /// once here rather than per pair per step.
    var viewConeCosine: Float {
        cosf(min(max(viewConeHalfAngleDegrees.value, 0), 180) * .pi / 180)
    }

    // MARK: - Private

    /// One constant of ours, labelled as ours wherever it is reported.
    private static func ours(_ value: Float) -> MovementSetting {
        MovementSetting(value: value, source: "OpenSky constant")
    }

    /// Builds a whole set: `override` supplies a load-order value where one
    /// exists, and every setting it declines falls back to the vanilla number
    /// under `loadOrderSource`.
    ///
    /// One builder rather than two initializer call sites, so the synthetic set
    /// and the resolved set cannot drift apart in either their numbers or their
    /// field order.
    private static func make(
        loadOrderSource: String,
        override: (String) -> MovementSetting?
    ) -> DetectionSettings {
        func vanilla(_ editorID: String, _ fallback: Float) -> MovementSetting {
            override(editorID) ?? MovementSetting(value: fallback, source: loadOrderSource)
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
            distanceAttenuationExponent: ours(2),
            equippedWeightBase: ours(12),
            equippedWeightMult: ours(0.5),
            sneakMovementMult: ours(0.75),
            sprintMovementMult: ours(3),
            viewConeHalfAngleDegrees: ours(90),
            visualBaseValue: ours(40),
            sneakVisualMult: ours(0.5),
            fullDetectionValue: ours(25),
            gainPerSecond: ours(100),
            decayPerSecond: ours(20),
            suspiciousLevel: ours(25),
            detectedLevel: ours(100)
        )
    }
}
