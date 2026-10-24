// The load order's combat data, grouped so the combat coordinator takes it
// whole in its initializer.

import OpenSkyCombatInterface
import OpenSkyGameData

/// What the combat runtimes are built from. The game settings default to the
/// vanilla values, so a test sets only the ones it checks.
public struct CombatSessionData {
    public var combat: CombatSettings
    public var archery: ArcherySettings
    /// The WEAP, AMMO and PROJ index.
    public var items: ItemDefinitionStore?
    public var impacts: MeleeImpactResolver?
    public var difficulty = DifficultySettings.synthetic
    public var weaponDamage = WeaponDamageSettings.vanilla
    public var stamina = StaminaSettings.vanilla
    public var powerAttacks = PowerAttackSettings.vanilla
    public var skillUses = MeleeSkillUseSettings.vanilla
    public var staggers = StaggerSettings.vanilla
    public var combatAI = CombatAISettings.vanilla
    public var arrows = ArrowSettings.vanilla

    public init(
        combat: CombatSettings,
        archery: ArcherySettings,
        items: ItemDefinitionStore? = nil,
        impacts: MeleeImpactResolver? = nil
    ) {
        self.combat = combat
        self.archery = archery
        self.items = items
        self.impacts = impacts
    }
}
