// The shell of the combat domain: owns the melee, archery and combat-loop
// runtimes, steps them each frame, and is the world all three resolve through.
// The decisions live in `CombatCore`. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// Owns the combat runtimes and reads the world through `CombatWorld`.
public final class CombatCoordinator {
    /// Nil until `wireMelee`. The readouts then report themselves unavailable.
    public private(set) var melee: MeleeCombatRuntime?
    public private(set) var archery: ArcheryRuntime?
    public private(set) var loop: CombatLoopRuntime?
    /// Every explosion: projectile, spell, and forced detonations share it.
    public let explosions = ExplosionRuntime()
    /// The WEAP, AMMO and PROJ index the hands and arrows resolve through.
    public private(set) var items: ItemDefinitionStore?
    /// Fighting actors may cast their spells unless the readout turns it off.
    public private(set) var allowsActorCasting = true
    /// Confidence decides engaging and fleeing, and Assistance brings allies into a
    /// fight. Off keeps the flat health-fraction rule and lone fighters.
    public var usesTemperament = true
    public internal(set) var actorCastCount = 0
    let world: any CombatWorld
    /// What this step asked of the app. A frame step returns and empties it.
    var pendingCommands: [CombatCommand] = []
    public internal(set) var lastMeleeAction = MeleeActionOutcome.idle
    public internal(set) var lastArcheryAction = ArcheryActionOutcome.idle
    /// The stuck arrows this coordinator spawned, so a reset removes only those.
    var stuckKeys: Set<ReferenceKey> = []
    /// The Difficulty setting; the app sets it from the settings store.
    public var difficulty = DifficultyLevel.default
    public var difficultySettings = DifficultySettings.synthetic
    /// Skill, sneak-attack, and armour settings; the app sets them from the load order.
    public var weaponDamage = WeaponDamageSettings.vanilla
    /// What a block costs; the app sets it from the load order.
    public var stamina = StaminaSettings.vanilla
    /// Power attacks and bashes; the app sets them before `wireMelee`.
    public var powerAttacks = PowerAttackSettings.vanilla
    /// The Block experience of blocks and bashes; the app sets it before `wireMelee`.
    public var skillUses = MeleeSkillUseSettings.vanilla
    /// Stagger and disarm chances; the app sets them before `wireMelee` and `wireLoop`.
    public var staggers = StaggerSettings.vanilla
    /// The game's combat AI settings; the app sets them before `wireLoop`.
    public var combatAI = CombatAISettings.vanilla
    /// Whether fights that start from now on use the game's advance, range, healing,
    /// shout, and flight settings. Off keeps OpenSky's own numbers.
    public var appliesCombatGameSettings = false {
        didSet { loop?.applyingGameSettings = appliesCombatGameSettings }
    }

    /// What a landed arrow does; the app sets it before `wireArchery`.
    public var arrows = ArrowSettings.vanilla
    /// The actor the player last hurt. The HUD shows its name and health.
    public internal(set) var playerStruckTarget: ReferenceKey?
    /// The critical-hit and arrow-deflect rolls.
    var strikeRandom = ConditionRandom()
    /// The player's crouch last frame, so a sneak entry casts its perk spell once.
    var wasPlayerSneaking = false
    /// The graph flags the player's perks set true last frame.
    var perkGraphFlags: Set<String> = []

    public init(world: any CombatWorld) {
        self.world = world
    }

    public func wireMelee(
        settings: CombatSettings,
        items: ItemDefinitionStore?,
        impacts: MeleeImpactResolver?
    ) {
        let runtime = MeleeCombatRuntime(settings: settings, world: self)
        runtime.impacts = impacts
        runtime.powerAttacks = powerAttacks
        runtime.skillUses = skillUses
        runtime.staggers = staggers
        self.items = items ?? self.items
        melee = runtime
    }

    public func wireArchery(
        settings: ArcherySettings,
        items: ItemDefinitionStore?,
        impacts: MeleeImpactResolver?
    ) {
        let projectiles = ProjectileRuntime(settings: settings, world: self)
        projectiles.impacts = impacts
        projectiles.explosions = explosions
        projectiles.arrows = arrows
        let runtime = ArcheryRuntime(settings: settings, projectiles: projectiles, world: self)
        self.items = items ?? self.items
        archery = runtime
    }

    public func wireLoop(settings: CombatSettings) {
        let runtime = CombatLoopRuntime(settings: settings, world: self)
        runtime.skillUses = skillUses
        runtime.staggers = staggers
        runtime.combatAI = combatAI
        runtime.applyingGameSettings = appliesCombatGameSettings
        loop = runtime
    }

    /// One frame of melee. The caller drains `events` every frame, even when
    /// the player is not in control, so no backlog resolves later.
    public func advanceMelee(
        events: [String], intent: MeleeIntent, isPlayerControlled: Bool
    ) -> [CombatCommand] {
        defer { pendingCommands = [] }
        guard let melee, isPlayerControlled else { return pendingCommands }
        let readied = readiedHands()
        let hands = CombatCore.hands(worn: wornItems(), readied: readied)
        melee.weapon = hands.weapon
        melee.offHand = hands.offHand
        let swing = melee.state.swingID
        melee.acceptFrame(CombatCore.meleeIntent(intent, readied: readied))
        noteHits(melee.handleGraphEvents(events))
        noteWeaponUse(.swing, changed: melee.state.swingID != swing)
        return pendingCommands
    }

    /// One frame of archery. Projectiles fly on outside player control, so an
    /// arrow does not freeze mid-air when the camera leaves walk mode.
    public func advanceArchery(
        events: [String],
        intent: ArcheryIntent,
        isPlayerControlled: Bool,
        delta: Float
    ) -> [CombatCommand] {
        defer { pendingCommands = [] }
        guard let archery else { return pendingCommands }
        if isPlayerControlled {
            archery.bow = CombatCore.bow(worn: wornItems())
            archery.arrow = selectedArrow()
            archery.attackMultiplier = archeryAttackMultiplier()
            var intent = intent
            intent.hasBowEquipped = archery.bow.weapon != nil
            let shots = archery.state.shotCount
            archery.acceptFrame(intent)
            archery.handleGraphEvents(events)
            noteWeaponUse(.shot, changed: archery.state.shotCount != shots)
        }
        // Every arrow provokes, a spell only when its effects are hostile.
        let struck = archery.advanceProjectiles(by: delta).filter(\.provokes)
        let targets = struck.compactMap(\.target)
        if !targets.isEmpty, let loop {
            let staggered = targets.filter { _ in loop.rollsStagger() }
            loop.notePlayerHits(targets, staggered: Set(staggered))
        }
        return pendingCommands
    }

    /// Steps the loop after melee, archery and the ragdolls, because it reads
    /// what they did this frame.
    public func advanceLoop(by delta: Float) -> [CombatCommand] {
        loop?.advance(by: delta)
        return takeCommands()
    }

    /// Drops what a reload cannot reproduce. Called on both sides of a save.
    public func prepareForPersistence() -> [CombatCommand] {
        loop?.prepareForPersistence()
        return takeCommands()
    }

    /// Returns and empties what this step asked of the app. A command raised outside
    /// a frame step, such as by a readout, also leaves with the next frame step.
    public func takeCommands() -> [CombatCommand] {
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// Turning casting off drops every cast in flight, so no charge is left
    /// that nothing will release.
    public func setActorCasting(_ allowed: Bool) {
        allowsActorCasting = allowed
        guard !allowed, let loop else { return }
        for key in loop.behaviors.keys.sorted() {
            world.cancelCast(by: key)
        }
        loop.record(.castingDisallowed)
    }

    /// Sets hostility on the readout's selected actor and records the outcome.
    public func setSelectedActorHostile(_ hostile: Bool) {
        guard let loop else { return }
        guard let key = world.selectedActor() else {
            loop.record(.noHostilityTarget)
            return
        }
        loop.setHostility(hostile ? .hostile : .neutral, on: key)
        loop.record(.hostility(actor: actorName(key), hostile: hostile))
    }

    private func noteWeaponUse(_ use: CombatWeaponUse, changed: Bool) {
        guard changed, loop?.isPlayerInCombat != true else { return }
        pendingCommands.append(.playerAttackedOutsideCombat(use))
    }

    func noteHits(_ hits: [MeleeHitRecord]) {
        guard !hits.isEmpty else { return }
        loop?.notePlayerHits(
            hits.map(\.target), staggered: Set(hits.filter(\.staggered).map(\.target))
        )
    }

    func readiedHands() -> ReadiedHands {
        ReadiedHands(
            right: world.hasReadiedSpell(in: .right),
            left: world.hasReadiedSpell(in: .left)
        )
    }

    func wornItems() -> [CombatWornItem] {
        guard let equipment = world.equipment, let items else { return [] }
        return equipment.equipped(on: .player).map { item in
            if let weapon = items.weapon(item) {
                let enchantment = world.enchantmentProfile(of: item)
                return .weapon(MeleeWeaponProfile(weapon: weapon, enchantment: enchantment)
                    .tempered(level: world.temperLevel(of: item)))
            }
            return equipment.occupancy(of: item).slots.contains(.shield) ? .shield : .other
        }
    }

    /// The first weapon the player has equipped, or nil when unarmed.
    public func playerWeapon() -> Weapon? {
        guard let equipment = world.equipment, let items else { return nil }
        return equipment.equipped(on: .player).lazy.compactMap { items.weapon($0) }.first
    }

    func selectedArrow() -> ArcheryAmmunition? {
        guard let items else { return nil }
        return CombatCore.arrow(
            carried: world.playerCarriedItems(),
            resolve: items.archeryAmmunition
        )
    }

    func archeryAttackMultiplier() -> Float {
        guard let values = world.actorValues(of: .player) else { return 1 }
        return CombatFortifyBonus.archery(reading: values)
    }

    /// The name `residentActors()` gives `key`, so the readouts agree.
    func actorName(_ key: ReferenceKey?) -> String {
        guard let key else { return "—" }
        return world.residentActors().first { $0.key == key }?.name ?? key.description
    }
}
