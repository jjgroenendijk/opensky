// Session wiring for melee combat: builds the runtime over the provider's
// combat GMSTs and weapon index, feeds it the frame's melee intent and graph
// events, and answers the world questions a landed hit asks. The frame hook
// shares `Renderer.onFrame` with the HUD, not the audio tick: a swing must
// resolve with audio off.

import AppKit
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyRendering
import OpenSkyWorld
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
    func wireMelee(provider: any WorldDataProviding, renderer: Renderer) {
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
        let hands = equippedHands()
        runtime.weapon = hands.weapon
        runtime.offHand = hands.offHand
        // A hand holding a readied spell takes its own button, the
        // same way a drawn bow takes the attack press away from the swing. The
        // intent is cleared rather than the runtime being told about spells,
        // because whether a hand is casting is the caster runtime's fact and
        // melee has no business holding a second copy of it.
        var intent = renderer.locomotion.meleeIntent
        if hasReadiedSpell(in: .right) {
            intent.attack = false
        }
        if hasReadiedSpell(in: .left) {
            intent.block = false
        }
        runtime.acceptFrame(intent)
        // Every landed hit is also what turns its target hostile and interrupts
        // the dev target's own attack, so the combat loop is told here rather
        // than sweeping the trace for new entries.
        noteCombatHits(runtime.handleGraphEvents(events))
    }

    /// Both hands as the behavior graph counts them. A readied spell wins,
    /// because readying it unequipped that hand; `CombatHandType.spell` is what
    /// `magicbehavior.hkx` reads. A two-handed weapon fills both hands, a second
    /// WEAP is the off-hand one, and a shield is an ARMO using slot 39. Torches
    /// (LIGH) are not indexed, so a lit hand reports empty.
    func equippedHands() -> (weapon: MeleeWeaponProfile, offHand: CombatHandType) {
        let worn = wornHands()
        return (
            hasReadiedSpell(in: .right) ? .readiedSpell : worn.weapon,
            hasReadiedSpell(in: .left) ? .spell : worn.offHand
        )
    }

    /// The same three readings over worn equipment alone, before a readied
    /// spell is laid over either hand.
    private func wornHands() -> (weapon: MeleeWeaponProfile, offHand: CombatHandType) {
        guard let equipment = worldItems.equipment, let weapons = melee.weapons else {
            return (.unarmed, .handToHand)
        }
        var profiles: [MeleeWeaponProfile] = []
        var hasShield = false
        for item in equipment.equipped(on: .player) {
            if let weapon = weapons.weapon(item) {
                profiles.append(MeleeWeaponProfile(
                    weapon: weapon,
                    enchantment: enchantmentProfile(of: item)
                ))
            } else if equipment.occupancy(of: item).slots.contains(.shield) {
                hasShield = true
            }
        }
        guard let right = profiles.first else {
            return (.unarmed, hasShield ? .shield : .handToHand)
        }
        if right.handType.occupiesBothHands {
            return (right, right.handType)
        }
        if profiles.count > 1 {
            return (right, profiles[1].handType)
        }
        return (right, hasShield ? .shield : .handToHand)
    }
}
