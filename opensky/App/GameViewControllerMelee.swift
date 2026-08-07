// Session wiring for melee combat (issue #195, roadmap item 15.4): builds the
// runtime over the provider's combat GMSTs and weapon index, feeds it the
// frame's melee intent and the graph events the fixed steps fired, and answers
// the world questions a landed hit asks.
//
// AppKit stays in this controller satellite; the state machine, the sweep, the
// damage formula and the impact chain are all engine types that build into
// `openskycli` and are testable without a window.
//
// The frame hook shares `Renderer.onFrame` with the HUD and the actor-value
// meters. It deliberately does *not* share the audio tick that routes
// footsteps: footsteps are heard at the listener and stop with the audio
// engine, whereas a swing has to resolve whether audio is on or not. Both
// consumers read the same `LocomotionGraphEventQueue` through their own cursor,
// which is what item 15.4 promoted the queue to allow.

import AppKit
import simd

/// Melee state the controller owns. Extensions cannot add stored properties, so
/// it lives as one value on `GameViewController`.
struct MeleeBridgeState {
    /// The combat runtime, built by `wireMelee` when the provider can supply
    /// combat settings. nil without game data, and then the panel reports
    /// itself unavailable rather than showing a convincing zero.
    var runtime: MeleeCombatRuntime?
    /// WEAP lookup for the equipped weapon, from the provider's item index.
    var weapons: ItemDefinitionStore?
    /// Human-readable result of the last panel action.
    var lastActionText = "No melee action yet."
}

extension GameViewController {
    /// Builds the melee runtime over the provider's combat GMSTs.
    ///
    /// A provider with no combat settings — every synthetic scene — leaves the
    /// runtime nil. The item index and the impact resolver are separately
    /// optional on top of that: a session can swing without either, and then
    /// the swing is unarmed and silent rather than absent.
    func wireMelee(provider: any CellSceneProvider, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.combatSettings else {
            return
        }
        let runtime = MeleeCombatRuntime(settings: settings)
        melee.weapons = (provider as? ItemDataProviding)?.inventoryBaselines?.items
        if let footsteps = (provider as? AudioDataProviding)?.footstepStore {
            runtime.impacts = MeleeImpactResolver(footsteps: footsteps)
        }
        melee.runtime = runtime
        runtime.attach(world: self)
        renderer.onFrame.add { [weak self, weak renderer] _ in
            self?.advanceMelee(renderer: renderer)
        }
    }

    /// One frame of melee: intent in, fired graph events in, hits out.
    ///
    /// Drained unconditionally, even outside walk mode, for the same reason
    /// footsteps are: the cursor must not accumulate a backlog from a mode
    /// where nothing is acting on it and then resolve all of it at once the
    /// moment the player takes control again.
    func advanceMelee(renderer: Renderer?) {
        guard let renderer, let runtime = melee.runtime else { return }
        let events = renderer.locomotion.graphEvents.drain(
            renderer.locomotion.meleeEventConsumer
        )
        guard renderer.movementMode.isPlayerControlled else { return }
        runtime.weapon = equippedWeaponProfile()
        runtime.acceptFrame(renderer.locomotion.meleeIntent)
        runtime.handleGraphEvents(events)
    }

    /// The player's equipped weapon as a swing profile, or the unarmed profile
    /// when nothing equipped resolves to a WEAP.
    ///
    /// Reads the equipped set rather than caching, because equipping is a
    /// world-state write that can happen from the sidebar, from a script, or
    /// from a container, and a cache would need invalidating from all three.
    func equippedWeaponProfile() -> MeleeWeaponProfile {
        guard let equipment = worldItems.equipment, let weapons = melee.weapons else {
            return .unarmed
        }
        for item in equipment.equipped(on: .player) {
            if let weapon = weapons.weapon(item) {
                return MeleeWeaponProfile(weapon: weapon)
            }
        }
        return .unarmed
    }
}
