// The shell of the combat domain: owns the melee, archery and combat-loop
// runtimes, steps them each frame, and is the world all three resolve through.
// The decisions live in `CombatCore`. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// Owns the combat runtimes and reads the world through `CombatWorld`.
public final class CombatCoordinator {
    /// Nil until `wireMelee`. The panels then report themselves unavailable.
    public private(set) var melee: MeleeCombatRuntime?
    public private(set) var archery: ArcheryRuntime?
    public private(set) var loop: CombatLoopRuntime?
    /// Every explosion: projectile, spell, and sidebar detonations share it.
    public let explosions = ExplosionRuntime()
    /// The WEAP, AMMO and PROJ index the hands and arrows resolve through.
    public private(set) var items: ItemDefinitionStore?
    /// Fighting actors may cast their spells unless the panel turns it off.
    public private(set) var allowsActorCasting = true
    public internal(set) var actorCastCount = 0
    weak var world: (any CombatWorld)?
    var meleeActionText = "No melee action yet."
    var archeryActionText = "No shot taken yet."
    /// The stuck arrows this coordinator spawned, so a reset removes only those.
    var stuckKeys: Set<ReferenceKey> = []
    /// The Difficulty setting; the app sets it from the settings store.
    public var difficulty = DifficultyLevel.default
    public var difficultySettings = DifficultySettings.synthetic

    public init() {}

    public func attach(world: any CombatWorld) {
        self.world = world
    }

    public func wireMelee(
        settings: CombatSettings,
        items: ItemDefinitionStore?,
        impacts: MeleeImpactResolver?
    ) {
        let runtime = MeleeCombatRuntime(settings: settings)
        runtime.impacts = impacts
        self.items = items ?? self.items
        melee = runtime
        runtime.attach(world: self)
    }

    public func wireArchery(
        settings: ArcherySettings,
        items: ItemDefinitionStore?,
        impacts: MeleeImpactResolver?
    ) {
        let projectiles = ProjectileRuntime(settings: settings)
        projectiles.impacts = impacts
        projectiles.explosions = explosions
        let runtime = ArcheryRuntime(settings: settings, projectiles: projectiles)
        self.items = items ?? self.items
        archery = runtime
        runtime.attach(world: self)
    }

    public func wireLoop(settings: CombatSettings) {
        let runtime = CombatLoopRuntime(settings: settings)
        loop = runtime
        runtime.attach(world: self)
    }

    /// One frame of melee. The caller drains `events` every frame, even when
    /// the player is not in control, so no backlog resolves later.
    public func advanceMelee(events: [String], intent: MeleeIntent, isPlayerControlled: Bool) {
        guard let melee, isPlayerControlled else { return }
        let readied = readiedHands()
        let hands = CombatCore.hands(worn: wornItems(), readied: readied)
        melee.weapon = hands.weapon
        melee.offHand = hands.offHand
        melee.acceptFrame(CombatCore.meleeIntent(intent, readied: readied))
        noteHits(melee.handleGraphEvents(events).map(\.target))
    }

    /// One frame of archery. Projectiles fly on outside player control, so an
    /// arrow does not freeze mid-air when the camera leaves walk mode.
    public func advanceArchery(
        events: [String],
        intent: ArcheryIntent,
        isPlayerControlled: Bool,
        delta: Float
    ) {
        guard let archery else { return }
        if isPlayerControlled {
            archery.bow = CombatCore.bow(worn: wornItems())
            archery.arrow = selectedArrow()
            archery.attackMultiplier = archeryAttackMultiplier()
            var intent = intent
            intent.hasBowEquipped = archery.bow.weapon != nil
            archery.acceptFrame(intent)
            archery.handleGraphEvents(events)
        }
        // Every arrow provokes, a spell only when its effects are hostile.
        let struck = archery.advanceProjectiles(by: delta).filter(\.provokes)
        noteHits(struck.compactMap(\.target))
    }

    /// Steps the loop after melee, archery and the ragdolls, because it reads
    /// what they did this frame.
    public func advanceLoop(by delta: Float) {
        loop?.advance(by: delta)
    }

    /// Turning casting off drops every cast in flight, so no charge is left
    /// that nothing will release.
    public func setActorCasting(_ allowed: Bool) {
        allowsActorCasting = allowed
        guard !allowed, let loop else { return }
        for key in loop.behaviors.keys.sorted() {
            world?.cancelCast(by: key)
        }
        loop.record("Combat: fighters may not cast their spells.")
    }

    /// Sets hostility on the panel's selected actor and records the outcome.
    public func setSelectedActorHostile(_ hostile: Bool) {
        guard let loop else { return }
        guard let key = world?.selectedActor() else {
            loop.record("Hostility: no resident actor to act on.")
            return
        }
        loop.setHostility(hostile ? .hostile : .neutral, on: key)
        loop.record("Hostility: \(actorName(key)) is now \(hostile ? "hostile" : "neutral").")
    }

    func noteHits(_ targets: [ReferenceKey]) {
        guard !targets.isEmpty else { return }
        loop?.notePlayerHits(targets)
    }

    func readiedHands() -> ReadiedHands {
        ReadiedHands(
            right: world?.hasReadiedSpell(in: .right) ?? false,
            left: world?.hasReadiedSpell(in: .left) ?? false
        )
    }

    func wornItems() -> [CombatWornItem] {
        guard let equipment = world?.equipment, let items else { return [] }
        return equipment.equipped(on: .player).map { item in
            if let weapon = items.weapon(item) {
                let enchantment = world?.enchantmentProfile(of: item)
                return .weapon(MeleeWeaponProfile(weapon: weapon, enchantment: enchantment))
            }
            return equipment.occupancy(of: item).slots.contains(.shield) ? .shield : .other
        }
    }

    /// The first weapon the player has equipped, or nil when unarmed.
    public func playerWeapon() -> Weapon? {
        guard let equipment = world?.equipment, let items else { return nil }
        return equipment.equipped(on: .player).lazy.compactMap { items.weapon($0) }.first
    }

    func selectedArrow() -> ArcheryAmmunition? {
        guard let items, let world else { return nil }
        return CombatCore.arrow(
            carried: world.playerCarriedItems(),
            resolve: items.archeryAmmunition
        )
    }

    func archeryAttackMultiplier() -> Float {
        guard let world, let values = world.actorValues(of: .player) else { return 1 }
        return CombatFortifyBonus.archery(reading: values)
            * world.perkMultiplier(at: CombatCore.attackDamageEntryPoint, on: .player)
    }

    /// The name `residentActors()` gives `key`, so the readouts agree.
    func actorName(_ key: ReferenceKey?) -> String {
        guard let key else { return "—" }
        return world?.residentActors().first { $0.key == key }?.name ?? key.description
    }
}
