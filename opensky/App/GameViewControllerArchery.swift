// Session wiring for archery (issue #196, roadmap item 15.5): builds the shot
// and projectile runtimes over the provider's archery GMSTs and item index,
// feeds them the frame's archery intent and the graph events the fixed steps
// fired, and advances everything already in the air.
//
// AppKit stays in this controller satellite; the shot state machine, the flight
// model, the impact query, the damage formula and the stuck-arrow registry are
// all engine types that build into `openskycli` and are testable without a
// window.
//
// The frame hook shares `Renderer.onFrame` with melee and the HUD, and reads
// the same `LocomotionGraphEventQueue` through a cursor of its own — the third,
// after footsteps and melee. Item 15.4 promoted the queue from drain-once to
// one cursor per consumer precisely so this could be added without displacing
// either of them.
//
// One ordering rule is deliberate: projectiles are advanced *unconditionally*,
// outside the walk-mode gate the intent is behind. An arrow already in the air
// has to finish its flight whether or not the player still has control — the
// alternative is a shot that freezes mid-air when the camera switches to fly
// mode and resumes when it comes back.

import AppKit
import simd

/// Archery state the controller owns. Extensions cannot add stored properties,
/// so it lives as one value on `GameViewController`.
struct ArcheryBridgeState {
    /// The shot runtime, built by `wireArchery` when the provider can supply
    /// archery settings. nil without game data, and then the panel reports
    /// itself unavailable rather than showing a convincing zero.
    var runtime: ArcheryRuntime?
    /// AMMO and PROJ lookup, from the provider's item index.
    var items: ItemDefinitionStore?
    /// Human-readable result of the last panel action.
    var lastActionText = "No shot taken yet."
    /// Keys the runtime spawned stuck arrows under, so a reset can take back
    /// exactly what it put in the world and nothing else.
    var stuckKeys: Set<ReferenceKey> = []
}

extension GameViewController {
    /// Builds the archery runtimes over the provider's archery GMSTs.
    ///
    /// A provider with no archery settings — every synthetic scene — leaves the
    /// runtime nil. The item index and the impact resolver are separately
    /// optional on top of that: a session can fly a projectile without either,
    /// and then the shot carries no arrow and lands silently rather than not
    /// happening.
    func wireArchery(provider: any CellSceneProvider, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.archerySettings else {
            return
        }
        let projectiles = ProjectileRuntime(settings: settings)
        if let footsteps = (provider as? AudioDataProviding)?.footstepStore {
            projectiles.impacts = MeleeImpactResolver(footsteps: footsteps)
        }
        let runtime = ArcheryRuntime(settings: settings, projectiles: projectiles)
        archery.items = (provider as? ItemDataProviding)?.inventoryBaselines?.items
        archery.runtime = runtime
        runtime.attach(world: self)
        // `onWorldUpdate` rather than `onFrame`, and chained rather than
        // replaced, exactly as the actor-value tick chains onto the Papyrus
        // VM's: it is the one callback whose delta the renderer has already
        // gated through `FrameSimClock`, so a menu-paused frame delivers zero
        // and an arrow hangs in the air instead of finishing its flight behind
        // an open menu.
        let advanceOthers = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self, weak renderer] delta in
            advanceOthers?(delta)
            self?.advanceArchery(renderer: renderer, frameTime: delta)
        }
    }

    /// One frame of archery: intent in, fired graph events in, flight out.
    func advanceArchery(renderer: Renderer?, frameTime: Float) {
        guard let renderer, let runtime = archery.runtime else { return }
        let events = renderer.locomotion.graphEvents.drain(
            renderer.locomotion.archeryEventConsumer
        )
        if renderer.movementMode.isPlayerControlled {
            runtime.bow = equippedBowProfile()
            runtime.arrow = selectedArrow()
            runtime.attackMultiplier = archeryAttackMultiplier()
            var intent = renderer.locomotion.archeryIntent
            intent.hasBowEquipped = runtime.bow.weapon != nil
            runtime.acceptFrame(intent)
            runtime.handleGraphEvents(events)
        }
        // Outside the gate on purpose; see the file comment.
        // An arrow that struck an actor provokes it, for the same reason a
        // landed swing does (issue #374).
        noteCombatProjectileHits(runtime.advanceProjectiles(by: frameTime))
    }

    /// The player's equipped bow as a swing profile, or the unarmed profile
    /// when nothing equipped is one.
    ///
    /// Filtered on WEAP DNAM `animationType` rather than on a keyword: the
    /// animation type is the field that decides which attack set a weapon runs,
    /// and `.bow` is exactly the set that draws instead of swinging. Crossbows
    /// (`.crossbow`) are deliberately excluded — item 15.5 puts them out of
    /// scope, and the census has not been read for whether their draw is
    /// data-identical.
    func equippedBowProfile() -> MeleeWeaponProfile {
        guard let equipment = worldItems.equipment, let items = archery.items else {
            return .unarmed
        }
        for item in equipment.equipped(on: .player) {
            guard let weapon = items.weapon(item), weapon.animationType == .bow else {
                continue
            }
            return MeleeWeaponProfile(
                weapon: weapon,
                enchantment: enchantmentProfile(of: item)
            )
        }
        return .unarmed
    }

    /// The player's fortify multiplier for a bow shot (issue #472), read off the
    /// actor-value runtime through `CombatFortifyBonus`. 1 without one.
    func archeryAttackMultiplier() -> Float {
        guard let runtime = actorValues.runtime else { return 1 }
        let fortify = CombatFortifyBonus.archery { runtime.value(at: $0, on: .player) }
        // The same `Mod Attack Damage` entry point a swing reads: vanilla
        // authors Overdraw on it exactly as it authors Armsman, and a bow shot
        // folds it into the same `bonusMultiplier` term (issue #497).
        return fortify * perkMultiplier(
            at: GameViewController.attackDamageEntryPoint, on: .player
        )
    }

    /// The arrow a shot would consume: the first ammunition the player carries
    /// that resolves to a flyable PROJ.
    ///
    /// "First carried" rather than "equipped", because ammunition sits in its
    /// own EQUP slot that item 12.2 does not model, and picking the first
    /// carried arrow is a rule a reader can predict. It is also stable: the
    /// inventory reports its stacks in a fixed order.
    func selectedArrow() -> ArcheryAmmunition? {
        guard let runtime = worldItems.runtime, let items = archery.items else { return nil }
        for stack in runtime.inventory.inventory(of: runtime.player).stacks {
            if let arrow = items.archeryAmmunition(stack.item) {
                return arrow
            }
        }
        return nil
    }
}
