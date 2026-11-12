// The shell of the combat domain: owns the melee, archery and combat-loop
// runtimes and steps them each frame. The parts over `CombatShared` answer the
// runtimes; the decisions live in `CombatCore`. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyFormatsESM
public import OpenSkyGameData

/// Owns the combat runtimes and reads the world through `CombatWorld`.
public final class CombatCoordinator {
    let shared: CombatShared
    let meleeWorld: CombatMeleeWorldPart
    let projectileWorld: CombatProjectileWorldPart
    let loopWorld: CombatLoopWorldPart
    /// The readout's forced attacks and shots, and the combat switches.
    public let panels: CombatPanelControls

    /// Builds the melee, archery, and combat-loop runtimes. Without `data` all
    /// three stay nil.
    public init(
        world: any CombatWorld,
        data: CombatSessionData?,
        explosions: ExplosionRuntime = ExplosionRuntime()
    ) {
        let shared = CombatShared(world: world, data: data, explosions: explosions)
        self.shared = shared
        meleeWorld = CombatMeleeWorldPart(shared: shared)
        projectileWorld = CombatProjectileWorldPart(shared: shared)
        loopWorld = CombatLoopWorldPart(shared: shared)
        panels = CombatPanelControls(shared: shared)
        guard let data else { return }
        shared.melee = meleeWorld.makeRuntime(data)
        shared.archery = projectileWorld.makeRuntime(data)
        shared.loop = loopWorld.makeRuntime(data)
    }

    /// Nil without game data. The readouts then report themselves unavailable.
    public var melee: MeleeCombatRuntime? {
        shared.melee
    }

    public var archery: ArcheryRuntime? {
        shared.archery
    }

    public var loop: CombatLoopRuntime? {
        shared.loop
    }

    /// Every explosion: projectile, spell, and forced detonations share it.
    public var explosions: ExplosionRuntime {
        shared.explosions
    }

    /// The WEAP, AMMO and PROJ index the hands and arrows resolve through.
    public var items: ItemDefinitionStore? {
        shared.items
    }

    /// The Difficulty setting; the app sets it from the settings store.
    public var difficulty: DifficultyLevel {
        get { shared.difficulty }
        set { shared.difficulty = newValue }
    }

    /// A Slow Time effect runs; the app sets it each frame. A bow zoom cannot start then.
    public var isTimeSlowed: Bool {
        get { shared.isTimeSlowed }
        set { shared.isTimeSlowed = newValue }
    }

    /// The last fall that ended on the ground, for `state` reads.
    public var lastFall: FallOutcome? {
        shared.lastFall
    }

    /// One frame of melee. The caller drains `events` every frame, even when
    /// the player is not in control, so no backlog resolves later.
    public func advanceMelee(
        events: [String], intent: MeleeIntent, isPlayerControlled: Bool
    ) -> [CombatCommand] {
        CombatFrameSteps(shared: shared)
            .advanceMelee(events: events, intent: intent, isPlayerControlled: isPlayerControlled)
    }

    /// One frame of archery. Projectiles fly on outside player control, so an
    /// arrow does not freeze mid-air when the camera leaves walk mode.
    public func advanceArchery(
        events: [String],
        intent: ArcheryIntent,
        isPlayerControlled: Bool,
        delta: Float
    ) -> [CombatCommand] {
        CombatFrameSteps(shared: shared).advanceArchery(
            events: events, intent: intent, isPlayerControlled: isPlayerControlled, delta: delta
        )
    }

    /// Steps the loop after melee, archery and the ragdolls, because it reads
    /// what they did this frame.
    public func advanceLoop(by delta: Float) -> [CombatCommand] {
        shared.loop?.advance(by: delta)
        return takeCommands()
    }

    /// Drops what a reload cannot reproduce. Called on both sides of a save.
    public func prepareForPersistence() -> [CombatCommand] {
        shared.loop?.prepareForPersistence()
        return takeCommands()
    }

    /// Returns and empties what this step asked of the app. A command raised outside
    /// a frame step, such as by a readout, also leaves with the next frame step.
    public func takeCommands() -> [CombatCommand] {
        defer { shared.pendingCommands = [] }
        return shared.pendingCommands
    }
}
