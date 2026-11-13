import Foundation
public import OpenSkyInventoryInterface
public import OpenSkyWorldState

nonisolated extension LockpickingParameters {
    /// UESP: sweet spot `base * (0.82 + 0.6 * Level / 100) * perk`, partial zone
    /// `base * (0.775 + 1.5 * Level / 100)`, break time `base * (1 + 0.5 * Level / 100)`.
    /// `sweetSpotPerk` is the `Mod Lockpick Sweet Spot` result for the unmodified width.
    public static func make(
        difficulty: LockDifficulty,
        skill: Float,
        settings: LockpickingSettings,
        perks: LockpickingPerkValues = .none
    ) -> LockpickingParameters {
        let level = min(max(skill, 0), 100)
        let sweet = (settings.sweetSpot[difficulty] ?? 0)
            * (settings.sweetSpotSkillBase + settings.sweetSpotSkillMult * level)
        let partial = (settings.partialPick[difficulty] ?? 0)
            * (settings.partialSkillBase + settings.partialSkillMult * level)
        let breakTime = (settings.breakSeconds[difficulty] ?? 1)
            * (1 + settings.breakSkillMult * level)
        return LockpickingParameters(
            difficulty: difficulty,
            sweetSpotWidth: sweet * perks.sweetSpotFactor,
            partialWidth: partial,
            breakSeconds: breakTime,
            unbreakable: perks.unbreakable,
            startingArc: perks.startingArc,
            halfArc: settings.halfArc,
            widthPerBrokenPick: settings.brokenPicksMult
        )
    }
}
