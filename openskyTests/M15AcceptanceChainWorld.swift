// The four world seams the M15 gate's chain answers (issue #198), in a
// satellite of `M15AcceptanceChain.swift` for the type-length cap — the same
// split `GameViewController` makes across `GameViewControllerMeleeWorld`,
// `GameViewControllerArcheryWorld`, `GameViewControllerRagdollWorld` and
// `GameViewControllerCombatWorld`.
//
// Every answer below is the chain's own state read straight: where the capsule
// is, which actors exist, what the arena's collision holds, how to take health
// off a reference through `ActorValueRuntime`, how to raise an event on one of
// the two real graphs. Nothing is recorded-and-ignored the way a unit-test fake
// records: this is a session, not a stand-in for one, which is what makes the
// route an integration of the four runtimes rather than four runs in a row.
//
// One deliberate narrowing: impacts and sounds are dropped. Audio is M9's and
// resolving a SNDR here would need the install, which the headless half of the
// gate does not have.

@testable import opensky
import simd

// MARK: - Melee

extension M15AcceptanceChain: MeleeCombatWorld {
    var meleeAttacker: MeleeAttacker {
        MeleeAttacker(
            key: Self.player,
            feet: controller.feetPosition,
            capsule: controller.capsule,
            facing: camera.yaw
        )
    }

    func meleeTargets() -> [MeleeTarget] {
        [MeleeTarget(key: Self.opponent, feet: opponentFeet)]
    }

    func meleeMaterial(at position: SIMD3<Float>) -> FormID? {
        nil
    }

    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        combatBlock(of: target)
    }

    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        applyCombatDamage(amount, to: target)
    }

    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {}

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard let target else {
            bridge.raise(name)
            return bridge.status.raisedEvents.contains(name)
        }
        guard target == Self.opponent else { return false }
        return opponentGraph.raiseEvent(named: name)
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        bridge.write(value, to: name)
    }
}

// MARK: - Archery

extension M15AcceptanceChain: ProjectileWorld {
    var projectileShooter: ProjectileShooter {
        ProjectileShooter(
            key: Self.player,
            origin: controller.cameraPosition,
            aim: SIMD3<Float>(cos(camera.yaw), sin(camera.yaw), 0),
            isFirstPerson: true,
            location: Self.cell
        )
    }

    func projectileTargets() -> [MeleeTarget] {
        meleeTargets()
    }

    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        ShapeSweeper.firstHit(
            query: query,
            shapes: streamer.staticCollisionCandidates(overlapping: query.bounds)
        )
    }

    func projectileMaterial(at position: SIMD3<Float>) -> FormID? {
        nil
    }

    @discardableResult
    func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        applyCombatDamage(amount, to: target)
    }

    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {}

    @discardableResult
    func consumeArrow(_ ammunition: FormID) -> Bool {
        (try? inventory.remove(ammunition, count: 1, from: .player)) != nil
    }

    @discardableResult
    func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
        let key = nextSpawnKey()
        stuckArrows.append((key: key, arrow: arrow))
        return key
    }

    func removeStuckProjectile(_ key: ReferenceKey) {
        stuckArrows.removeAll { $0.key == key }
    }

    func residentProjectileCells() -> Set<CellSceneLocation> {
        [Self.cell]
    }

    @discardableResult
    func raiseArcheryEvent(_ name: String) -> Bool {
        raiseCombatEvent(name, on: nil)
    }

    func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {
        writeCombatVariable(value, named: name)
    }
}

// MARK: - Death and ragdolls

extension M15AcceptanceChain: RagdollWorldSeam {
    func ragdollActor(for key: ReferenceKey) -> RagdollActor? {
        guard key == Self.opponent else { return nil }
        return RagdollActor(
            key: key,
            cell: Self.cell,
            reference: Self.opponentReference,
            definition: RagdollFixture.limb().definition,
            animatedBoneMatrices: (0 ..< 3).map {
                MatrixMath.translation(
                    opponentFeet
                        + SIMD3(Float($0) * RagdollFixture.boneHalfLength * 2, 0, 90)
                )
            },
            actorToWorld: matrix_identity_float4x4
        )
    }

    @discardableResult
    func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool {
        raiseCombatEvent(name, on: key)
    }

    var ragdollStepWorld: DynamicStepWorld {
        M15AcceptanceWorld.stepWorld()
    }

    func writeDeathState(
        _ state: ActorDeathState, for key: ReferenceKey, in cell: CellSceneLocation
    ) {
        deathStates[key] = state
        store.set(state, for: key, in: cell)
    }

    func deathState(of key: ReferenceKey) -> ActorDeathState? {
        deathStates[key]
    }
}

// MARK: - The combat loop

extension M15AcceptanceChain: CombatLoopWorld {
    var combatPlayer: MeleeAttacker {
        meleeAttacker
    }

    func combatActors() -> [CombatActorObservation] {
        [CombatActorObservation(
            key: Self.opponent,
            feet: opponentFeet,
            facing: .pi,
            isDead: ragdolls.isDead(Self.opponent),
            name: "Opponent"
        )]
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        store.component(ActorCombatState.self, for: key)?.hostility ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        guard combatHostility(of: key) != hostility else { return false }
        store.set(ActorCombatState(hostility: hostility), for: key, in: Self.cell)
        return true
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        guard amount > 0 else { return false }
        let holder = key == Self.player ? ActorValueHolder.player : opponentHolder
        actorValues.damage(.health, by: amount, on: holder)
        return true
    }

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        guard key == Self.player else { return combat.blockKind(of: key) }
        return melee.state.isBlocking ? .weapon : nil
    }

    /// The opponent stands three feet in front of the player, facing them, in a
    /// lit arena with nothing between the two. What a perception pass would say
    /// about that pair is "detected", so the chain says it rather than standing
    /// up 16.6's whole formula to be told the same thing — and says nothing at
    /// all until the actor is hostile, which is what keeps the entry edge real.
    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness {
        guard combatHostility(of: observer) == .hostile else { return .unaware }
        return .detected(at: meleeAttacker.feet)
    }

    /// Against the health the chain *started* the actor at, not the derived
    /// maximum.
    ///
    /// The route deliberately gives the opponent 40 health so that one swing
    /// and one arrow are the whole fight, while the record-derived maximum is
    /// 100. Dividing by the maximum would put the opponent under the flee
    /// threshold after the first blow, and the gate would be measuring an actor
    /// running away rather than the fight it is about. Full is what the chain
    /// set, which is the honest reading of "how hurt is it".
    func combatHealthFraction(of key: ReferenceKey) -> Float {
        let holder = key == Self.player ? ActorValueHolder.player : opponentHolder
        let full = key == Self.player ? Self.playerHealth : Self.opponentHealth
        guard full > 0 else { return 1 }
        return min(1, max(0, actorValues.current(of: holder).health / full))
    }

    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile {
        MeleeWeaponProfile(damage: Self.opponentDamage, reach: 1)
    }

    /// The arena carries no navmesh, so no combat path is ever found. The
    /// opponent starts inside its own reach, which is the fight the gate is
    /// about; a refused move is the honest answer and the machine survives it.
    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        combatMoveRequests.append(point)
        return false
    }

    func stopCombatMovement(of key: ReferenceKey) {
        combatStopRequests += 1
    }

    func resumeCombatPackage(for key: ReferenceKey) {
        combatPackageResumes += 1
    }

    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        // The route draws no NPC, so there is no playback object to take a
        // clip. False is the honest answer and the readout reports it as such.
        false
    }

    var combatTransients: CombatTransientCounts {
        CombatTransientCounts(
            liveProjectiles: archery.projectiles.live.count,
            stuckProjectiles: stuckArrows.count,
            activeRagdolls: ragdolls.world.ragdollCount,
            awakeBodies: streamer.dynamicBodies.activeBodyCount
        )
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        let excess = limits.excess(over: combatTransients)
        archery.projectiles.removeOldestLive(excess.liveProjectiles)
        for entry in stuckArrows.prefix(excess.stuckProjectiles) {
            removeStuckProjectile(entry.key)
        }
        ragdolls.trim(to: limits.activeRagdolls)
        return excess
    }

    func despawnCombatTransients() {
        archery.projectiles.despawnAll()
        stuckArrows.removeAll()
        ragdolls.reset()
    }

    func setCombatMusicActive(_ active: Bool) {}
}
