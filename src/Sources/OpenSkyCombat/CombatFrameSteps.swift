// One frame of the player's melee and archery: the hands and arrow read from the
// gear, the intent handed to the runtimes, and the hits handed to the combat loop.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// The melee and archery steps of one frame, over the shared combat state.
struct CombatFrameSteps {
    let shared: CombatShared

    /// One frame of melee. The caller drains `events` every frame, even when
    /// the player is not in control, so no backlog resolves later.
    func advanceMelee(
        events: [String], intent: MeleeIntent, isPlayerControlled: Bool
    ) -> [CombatCommand] {
        defer { shared.pendingCommands = [] }
        let gear = shared.gear
        guard let melee = shared.melee, isPlayerControlled else { return shared.pendingCommands }
        let readied = gear.readiedHands()
        let hands = CombatCore.hands(worn: gear.wornItems(), readied: readied)
        melee.weapon = hands.weapon
        melee.offHand = hands.offHand
        let swing = melee.state.swingID
        melee.acceptFrame(CombatCore.meleeIntent(
            intent, readied: readied, staffInRight: hands.weapon.handType == .staff,
            bowAiming: shared.archery?.state.phase.isDrawing == true
        ))
        noteHits(melee.handleGraphEvents(events))
        noteWeaponUse(.swing, changed: melee.state.swingID != swing)
        return shared.pendingCommands
    }

    /// One frame of archery. Projectiles fly on outside player control, so an
    /// arrow does not freeze mid-air when the camera leaves walk mode.
    func advanceArchery(
        events: [String],
        intent: ArcheryIntent,
        isPlayerControlled: Bool,
        delta: Float
    ) -> [CombatCommand] {
        defer { shared.pendingCommands = [] }
        guard let archery = shared.archery else { return shared.pendingCommands }
        let gear = shared.gear
        if isPlayerControlled {
            archery.bow = CombatCore.bow(worn: gear.wornItems())
            archery.arrow = gear.selectedArrow()
            archery.attackMultiplier = gear.archeryAttackMultiplier()
            archery.zoomConditions = gear.bowZoomConditions(bow: archery.bow.weapon)
            var intent = intent
            intent.hasBowEquipped = archery.bow.weapon != nil
            let shots = archery.state.shotCount
            archery.acceptFrame(intent)
            for _ in archery.handleGraphEvents(events) {
                shared.pendingCommands.append(.playerBowShot(
                    weapon: archery.bow.weapon, ammunition: archery.arrow?.item,
                    power: archery.lastDrawFraction
                ))
            }
            gear.drainBowZoomStamina(bow: archery.bow.weapon, delta: delta)
            noteWeaponUse(.shot, changed: archery.state.shotCount != shots)
        }
        // Every arrow provokes, a spell only when its effects are hostile.
        let struck = archery.advanceProjectiles(by: delta).filter(\.provokes)
        let targets = struck.compactMap(\.target)
        if !targets.isEmpty, let loop = shared.loop {
            let staggered = targets.filter { _ in loop.rollsStagger() }
            loop.notePlayerHits(targets, staggered: Set(staggered))
        }
        return shared.pendingCommands
    }

    func noteWeaponUse(_ use: CombatWeaponUse, changed: Bool) {
        guard changed, shared.loop?.isPlayerInCombat != true else { return }
        shared.pendingCommands.append(.playerAttackedOutsideCombat(use))
    }

    func noteHits(_ hits: [MeleeHitRecord]) {
        guard !hits.isEmpty else { return }
        shared.loop?.notePlayerHits(
            hits.map(\.target), staggered: Set(hits.filter(\.staggered).map(\.target))
        )
    }
}
