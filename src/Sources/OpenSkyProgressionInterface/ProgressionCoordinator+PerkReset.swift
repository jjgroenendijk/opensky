import OpenSkyFormatsESM
import OpenSkyGameData

/// Why a tree was not cleared. Not a bool, because the skills menu and the readout show it.
nonisolated public enum PerkTreeResetRefusal: Error, Equatable, Sendable {
    case notASkill
    /// No leveling or no perk data in this session.
    case noProgression
    /// A legendary skill needs a base of 100; carries the base it has.
    case belowLegendaryLevel(Float)
    case noDragonSoul
    /// The altar refuses a tree with nothing to refund (`DLC2AltarNoPerksInThisSkillMSG`).
    case noPerksInTree
}
