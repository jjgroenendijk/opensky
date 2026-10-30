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
    /// Nil without game data. The readouts then report themselves unavailable.
    public private(set) var melee: MeleeCombatRuntime?
    public private(set) var archery: ArcheryRuntime?
    public private(set) var loop: CombatLoopRuntime?
    /// Every explosion: projectile, spell, and forced detonations share it.
    public let explosions: ExplosionRuntime
    /// The WEAP, AMMO and PROJ index the hands and arrows resolve through.
    public let items: ItemDefinitionStore?
    /// Fighting actors may cast their spells unless the readout turns it off.
    public private(set) var allowsActorCasting = true
    /// Confidence decides engaging and fleeing, and Assistance brings allies into a
    /// fight. Off keeps the flat health-fraction rule and lone fighters.
    public var usesTemperament = true
    /// A Slow Time effect runs; the app sets it each frame. A bow zoom cannot start then.
    public var isTimeSlowed = false
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
    public let difficultySettings: DifficultySettings
    /// Skill, sneak-attack, and armour settings.
    public let weaponDamage: WeaponDamageSettings
    /// What a block costs.
    public let stamina: StaminaSettings
    /// Stagger and disarm chances.
    public let staggers: StaggerSettings
    /// How much a fall hurts.
    public let falls: FallDamageSettings
    /// The last fall that ended on the ground, for `state` reads.
    public internal(set) var lastFall: FallOutcome?
    /// The game's combat AI settings.
    public let combatAI: CombatAISettings
    /// Whether fights that start from now on use the game's advance, range, healing,
    /// shout, and flight settings. Off keeps OpenSky's own numbers.
    public var appliesCombatGameSettings = false {
        didSet { loop?.applyingGameSettings = appliesCombatGameSettings }
    }

    /// The actor the player last hurt. The HUD shows its name and health.
    public internal(set) var playerStruckTarget: ReferenceKey?
    /// The critical-hit and arrow-deflect rolls.
    var strikeRandom = ConditionRandom()
    /// The player's crouch last frame, so a sneak entry casts its perk spell once.
    var wasPlayerSneaking = false
    /// The graph flags the player's perks set true last frame.
    var perkGraphFlags: Set<String> = []

    /// Builds the melee, archery, and combat-loop runtimes. Without `data` all
    /// three stay nil.
    public init(
        world: any CombatWorld,
        data: CombatSessionData?,
        explosions: ExplosionRuntime = ExplosionRuntime()
    ) {
        self.world = world
        self.explosions = explosions
        items = data?.items
        difficultySettings = data?.difficulty ?? .synthetic
        weaponDamage = data?.weaponDamage ?? .vanilla
        stamina = data?.stamina ?? .vanilla
        staggers = data?.staggers ?? .vanilla
        combatAI = data?.combatAI ?? .vanilla
        falls = data?.falls ?? .vanilla
        guard let data else { return }
        buildMelee(data)
        buildArchery(data)
        buildLoop(data)
    }

    private func buildMelee(_ data: CombatSessionData) {
        let runtime = MeleeCombatRuntime(settings: data.combat, world: self)
        runtime.impacts = data.impacts
        runtime.powerAttacks = data.powerAttacks
        runtime.skillUses = data.skillUses
        runtime.staggers = data.staggers
        melee = runtime
    }

    private func buildArchery(_ data: CombatSessionData) {
        let projectiles = ProjectileRuntime(settings: data.archery, world: self)
        projectiles.impacts = data.impacts
        projectiles.explosions = explosions
        projectiles.arrows = data.arrows
        archery = ArcheryRuntime(settings: data.archery, projectiles: projectiles, world: self)
    }

    private func buildLoop(_ data: CombatSessionData) {
        let runtime = CombatLoopRuntime(settings: data.combat, world: self)
        runtime.skillUses = data.skillUses
        runtime.staggers = data.staggers
        runtime.combatAI = data.combatAI
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
            archery.zoomConditions = bowZoomConditions(bow: archery.bow.weapon)
            var intent = intent
            intent.hasBowEquipped = archery.bow.weapon != nil
            let shots = archery.state.shotCount
            archery.acceptFrame(intent)
            for _ in archery.handleGraphEvents(events) {
                pendingCommands.append(.playerBowShot(
                    weapon: archery.bow.weapon, ammunition: archery.arrow?.item,
                    power: archery.lastDrawFraction
                ))
            }
            drainBowZoomStamina(bow: archery.bow.weapon, delta: delta)
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
