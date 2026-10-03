// The lockpicking numbers: per-difficulty arcs and skill uses from the install's
// GMSTs, and the parts no setting names from UESP "Skyrim:Lockpicking".
// See docs/engine/locks.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// Tuning for one lockpicking session, resolved once per session start.
nonisolated public struct LockpickingSettings: Equatable, Sendable {
    /// `fSweetSpot<band>`: the sweet-spot width in degrees before skill and perks.
    public var sweetSpot: [LockDifficulty: Float]
    /// `fPartialPick<band>`: the width of each partial zone in degrees.
    public var partialPick: [LockDifficulty: Float]
    /// `fSkillUsageLockPick<band>`: skill uses an opened lock reports.
    public var successUses: [LockDifficulty: Float]
    /// `fSkillUsageLockPickBroken`.
    public var brokenUses: Float
    /// `fLockpickSkillSweetSpotMult`: sweet-spot factor gained per skill point.
    public var sweetSpotSkillMult: Float
    /// The sweet-spot factor at skill 0. UESP: `0.82 + 0.6 * Level / 100`. No GMST.
    public var sweetSpotSkillBase: Float
    /// `fLockpickSkillPartialPickBase` and `...Mult`, the same shape for the partial zones.
    public var partialSkillBase: Float
    public var partialSkillMult: Float
    /// Seconds of straining that break a pick at skill 0. UESP; no GMST.
    public var breakSeconds: [LockDifficulty: Float]
    /// UESP: skill multiplies the break time by `1 + 0.5 * Level / 100`.
    public var breakSkillMult: Float
    /// The pick's travel, in degrees either side of upright. UESP: "a 180 degree arc".
    public var halfArc: Float

    public static let documentedDefaults = LockpickingSettings(
        sweetSpot: [.novice: 30, .apprentice: 15, .adept: 7.5, .expert: 3.75, .master: 1.875],
        partialPick: [.novice: 22, .apprentice: 18, .adept: 14, .expert: 10, .master: 6],
        successUses: [.novice: 2, .apprentice: 3, .adept: 5, .expert: 8, .master: 13],
        brokenUses: 0.25,
        sweetSpotSkillMult: 0.006,
        sweetSpotSkillBase: 0.82,
        partialSkillBase: 0.775,
        partialSkillMult: 0.015,
        breakSeconds: [.novice: 2, .apprentice: 1, .adept: 0.75, .expert: 0.5, .master: 0.25],
        breakSkillMult: 0.005,
        halfArc: 90
    )

    public init(
        sweetSpot: [LockDifficulty: Float],
        partialPick: [LockDifficulty: Float],
        successUses: [LockDifficulty: Float],
        brokenUses: Float,
        sweetSpotSkillMult: Float,
        sweetSpotSkillBase: Float,
        partialSkillBase: Float,
        partialSkillMult: Float,
        breakSeconds: [LockDifficulty: Float],
        breakSkillMult: Float,
        halfArc: Float
    ) {
        self.sweetSpot = sweetSpot
        self.partialPick = partialPick
        self.successUses = successUses
        self.brokenUses = brokenUses
        self.sweetSpotSkillMult = sweetSpotSkillMult
        self.sweetSpotSkillBase = sweetSpotSkillBase
        self.partialSkillBase = partialSkillBase
        self.partialSkillMult = partialSkillMult
        self.breakSeconds = breakSeconds
        self.breakSkillMult = breakSkillMult
        self.halfArc = halfArc
    }

    /// The defaults with every setting the load order defines laid over them.
    public static func resolve(store: GameSettingStore) -> LockpickingSettings {
        var settings = documentedDefaults
        func float(_ name: String) -> Float? {
            guard
                case let .float(value)? = store.setting(editorID: name)?.setting.value,
                value.isFinite, value >= 0
            else { return nil }
            return value
        }
        for band in LockDifficulty.allCases where band.isPickable {
            let suffix = band.settingSuffix
            settings.sweetSpot[band] = float("fSweetSpot\(suffix)") ?? settings.sweetSpot[band]
            settings.partialPick[band] = float("fPartialPick\(suffix)")
                ?? settings.partialPick[band]
            settings.successUses[band] = float("fSkillUsageLockPick\(suffix)")
                ?? settings.successUses[band]
        }
        settings.brokenUses = float("fSkillUsageLockPickBroken") ?? settings.brokenUses
        settings.sweetSpotSkillMult = float("fLockpickSkillSweetSpotMult")
            ?? settings.sweetSpotSkillMult
        settings.partialSkillBase = float("fLockpickSkillPartialPickBase")
            ?? settings.partialSkillBase
        settings.partialSkillMult = float("fLockpickSkillPartialPickMult")
            ?? settings.partialSkillMult
        return settings
    }
}
