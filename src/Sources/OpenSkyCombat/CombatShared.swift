// The state `CombatCoordinator` and its parts share. The parts are small values over
// it, so each reads the runtimes and settings without holding the coordinator.

import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// The world, the runtimes, the settings, and what one frame step collects.
final class CombatShared {
    let world: any CombatWorld
    let items: ItemDefinitionStore?
    let explosions: ExplosionRuntime
    let perks: CombatPerkTerms
    var melee: MeleeCombatRuntime?
    var archery: ArcheryRuntime?
    var loop: CombatLoopRuntime?
    let difficultySettings: DifficultySettings
    let weaponDamage: WeaponDamageSettings
    let stamina: StaminaSettings
    let staggers: StaggerSettings
    let falls: FallDamageSettings
    let combatAI: CombatAISettings
    var difficulty = DifficultyLevel.default
    /// What this step asked of the app. A frame step returns and empties it.
    var pendingCommands: [CombatCommand] = []
    /// The stuck arrows this coordinator spawned, so a reset removes only those.
    var stuckKeys: Set<ReferenceKey> = []
    var playerStruckTarget: ReferenceKey?
    var lastFall: FallOutcome?
    var isTimeSlowed = false
    var usesTemperament = true
    var allowsActorCasting = true
    var appliesCombatGameSettings = false
    var actorCastCount = 0

    init(world: any CombatWorld, data: CombatSessionData?, explosions: ExplosionRuntime) {
        self.world = world
        self.explosions = explosions
        items = data?.items
        difficultySettings = data?.difficulty ?? .synthetic
        weaponDamage = data?.weaponDamage ?? .vanilla
        stamina = data?.stamina ?? .vanilla
        staggers = data?.staggers ?? .vanilla
        combatAI = data?.combatAI ?? .vanilla
        falls = data?.falls ?? .vanilla
        perks = CombatPerkTerms(world: world, items: data?.items, staggers: staggers)
    }

    var strikes: CombatShared.CombatStrikes {
        CombatShared.CombatStrikes(shared: self)
    }

    var damage: CombatShared.CombatDamage {
        CombatShared.CombatDamage(shared: self)
    }

    var gear: CombatShared.CombatGear {
        CombatShared.CombatGear(shared: self)
    }

    /// The player's place, or the origin facing +Y before the world places one.
    var meleeAttacker: MeleeAttacker {
        world.playerAttacker ?? MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    }
}
