// One frame of the player's melee and archery: the hands and arrow read from the
// gear, the intent handed to the runtimes, and the hits handed to the combat loop.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
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
        melee.leftWeapon = hands.leftWeapon
        let swing = melee.state.swingID
        melee.acceptFrame(CombatCore.meleeIntent(
            intent, readied: readied, staffInRight: hands.weapon.handType == .staff,
            bowAiming: shared.archery?.state.phase.isDrawing == true,
            leftArmed: hands.leftWeapon != nil
        ))
        noteHits(melee.handleGraphEvents(events))
        noteWeaponUse(.swing, changed: melee.state.swingID != swing)
        if melee.state.swingID != swing, let weapon = melee.weapon.weapon {
            shared.pendingCommands.append(.playerUsedWeapon(weapon))
        }
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
            archery.arrow = gear.selectedArrow(bolts: archery.bow.handType == .crossbow)
            archery.attackMultiplier = gear.archeryAttackMultiplier()
            archery.zoomConditions = gear.bowZoomConditions(bow: archery.bow.weapon)
            var intent = intent
            intent.hasBowEquipped = archery.bow.weapon != nil
            intent.weaponDrawn = shared.melee.map { $0.state.drawState == .drawn } ?? true
            let shots = archery.state.shotCount
            archery.acceptFrame(intent)
            for _ in archery.handleGraphEvents(events) {
                shared.pendingCommands.append(.playerBowShot(
                    weapon: archery.bow.weapon, ammunition: archery.arrow?.item,
                    power: archery.lastDrawFraction
                ))
                if let bow = archery.bow.weapon {
                    shared.pendingCommands.append(.playerUsedWeapon(bow))
                }
            }
            gear.drainBowZoomStamina(bow: archery.bow.weapon, delta: delta)
            noteWeaponUse(.shot, changed: archery.state.shotCount != shots)
        }
        // Every arrow provokes, a spell only when its effects are hostile.
        let struck = archery.advanceProjectiles(by: delta).filter(\.provokes)
        if let loop = shared.loop {
            let staggered = struck.compactMap { arrowStagger($0, bow: archery.bow, loop: loop) }
            let targets = struck.filter { $0.shooter ?? .player == .player }.compactMap(\.target)
            if !targets.isEmpty {
                loop.notePlayerHits(targets, staggered: Set(staggered))
            }
        }
        return shared.pendingCommands
    }

    /// The target of a landed arrow when the hit staggers it, by the rule of a melee
    /// hit. A spell projectile has no stagger value, so its magnitude is 0.
    /// docs/engine/hit-reactions.md.
    func arrowStagger(
        _ trace: ProjectileTrace, bow: MeleeWeaponProfile, loop: CombatLoopRuntime
    ) -> ReferenceKey? {
        guard let target = trace.target, trace.spellHit == nil, trace.appliedDamage > 0
        else { return nil }
        var hit = HitReactionHit()
        let attacker = trace.shooter ?? .player
        let fromPlayer = attacker == .player
        hit.facts = shared.strikes.hitFacts(
            attacker: attacker, target: target, event: "",
            weaponStagger: fromPlayer ? bow.stagger : trace.arrow?.stagger ?? 0
        )
        hit.handType = fromPlayer ? bow.handType : trace.arrow?.handType ?? .bow
        hit.isMelee = false
        hit.isPlayerTarget = target == .player
        let reaction = HitReactionRule.reaction(
            hit, roll: loop.staggerRandom.percent(), settings: loop.staggers
        )
        shared.note(HitReactionReport(
            attacker: attacker, target: target, hit: hit, reaction: reaction
        ))
        guard let magnitude = reaction.staggerMagnitude else { return nil }
        let world = shared.world
        guard target != .player else {
            world.writePlayerGraphVariable(
                .real(magnitude), named: CombatGraphNames.staggerMagnitude
            )
            world.writePlayerGraphVariable(
                .real(hit.facts.direction), named: CombatGraphNames.staggerDirection
            )
            world.raisePlayerGraphEvent(CombatGraphNames.staggerStart)
            return target
        }
        world.writeActorGraphVariable(
            .real(magnitude), named: CombatGraphNames.staggerMagnitude, on: target
        )
        world.writeActorGraphVariable(
            .real(hit.facts.direction), named: CombatGraphNames.staggerDirection, on: target
        )
        _ = world.raiseActorGraphEvent(CombatGraphNames.staggerStart, on: target)
        return target
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
