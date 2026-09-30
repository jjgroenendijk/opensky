// The numbers detection resolves its formula from, resolved once at setup, each
// naming its source. GMSTs come from the load order, with install-observed
// fallbacks (UESP's `fSneakDistanceAttenuationExponent` does not exist). Values
// no record documents, such as the view cone, are marked "OpenSky constant".
// Light, muffle, and skill stay pinned in `DetectionFormula`.
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
    public let sneakBaseValue: MovementSetting
    /// `fSneakMaxDistance` — the range past which sight and hearing both
    /// attenuate to nothing, world units.
    public let maxDistance: MovementSetting
    /// `fSneakExteriorDistanceMult` — what that range is multiplied by outdoors,
    /// where there are no walls to stop either sense.
    public let exteriorDistanceMult: MovementSetting
    /// `fSneakSoundsMult` — what the whole sound term is multiplied by.
    public let soundsMult: MovementSetting
    /// `fSneakSoundLosMult` — what the sound term is multiplied by when nothing
    /// can see through to the target. Sound reaches around a corner; it just
    /// reaches less.
    public let soundLosMult: MovementSetting
    /// `fSneakRunningMult` — how much louder a running target is than a walking
    /// one.
    public let runningMult: MovementSetting
    /// `fSneakActionMult` — what an action sound is multiplied by. OpenSky feeds
    /// no action sounds yet, so this multiplies a pinned zero; it is resolved
    /// anyway so the term is wired rather than absent.
    public let actionMult: MovementSetting
    /// `fSneakSkillMult` — what a skill level is multiplied by to become a skill
    /// factor. Both skills are pinned (see `DetectionFormula`), so this weights
    /// a documented constant rather than a stored actor value.
    public let skillMult: MovementSetting
    /// `fSneakPerceptionSkillMin` and `fSneakPerceptionSkillMax` — the range a
    /// skill level is clamped to before it is weighted.
    public let perceptionSkillMin: MovementSetting
    public let perceptionSkillMax: MovementSetting

    // MARK: - OpenSky's own

    /// The exponent the distance attenuation is raised to. UESP names an
    /// `fSneakDistanceAttenuationExponent` of 2; no GMST of that editor ID
    /// exists on the install, so the exponent is ours and says so.
    public let distanceAttenuationExponent: MovementSetting
    /// The `fSneakEquippedWeightBase` term of the movement-noise formula — what
    /// a target counts as wearing before anything is equipped. UESP names it as
    /// a setting; the install carries no GMST by that editor ID.
    public let equippedWeightBase: MovementSetting
    /// The `fSneakEquippedWeightMult` term, noise per point of equipped weight,
    /// on the same terms.
    public let equippedWeightMult: MovementSetting
    /// What movement noise is multiplied by while the target is sneaking.
    /// Vanilla's own movement term has no crouch factor at all — it spends the
    /// Sneak skill on the observer's side of the formula instead — and OpenSky
    /// has no skills to spend, so the gait is where sneaking has to pay.
    public let sneakMovementMult: MovementSetting
    /// The same for a sprinting target, one step above `fSneakRunningMult`.
    public let sprintMovementMult: MovementSetting
    /// Half-angle of an observer's view cone, degrees off its facing. 90 makes
    /// the cone a forward hemisphere: a target directly beside an observer is on
    /// the edge of sight and one behind it is not seen at all.
    public let viewConeHalfAngleDegrees: MovementSetting
    /// The visual term a lit, upright target in plain sight contributes. Scaled
    /// to sit alongside the sound term, whose vanilla base is 12.
    public let visualBaseValue: MovementSetting
    /// What the visual term is multiplied by while the target is sneaking.
    public let sneakVisualMult: MovementSetting
    /// Detection value at which the level climbs at its full rate. A stronger
    /// signal than this does not climb faster.
    public let fullDetectionValue: MovementSetting
    /// Detection level gained per second at a full-rate signal, out of 100.
    public let gainPerSecond: MovementSetting
    /// Detection level lost per second while nothing is perceived.
    public let decayPerSecond: MovementSetting
    /// Level at or above which an observer is suspicious and has somewhere to
    /// investigate.
    public let suspiciousLevel: MovementSetting
    /// Level at which an observer has detected the target outright. The top of
    /// the scale, so "detected" and "certain" are the same state.
    public let detectedLevel: MovementSetting

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
