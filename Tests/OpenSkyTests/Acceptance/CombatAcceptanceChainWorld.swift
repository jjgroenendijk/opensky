// The four world seams the M15 chain answers, split from
// `CombatAcceptanceChain.swift` for the type-length cap. Each answer reads the
// chain's real state, so the route integrates the four runtimes. Impacts and
// sounds are dropped: a SNDR needs the install.

@testable import OpenSkyActors
@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
@testable import OpenSkyProgressionInterface
@testable import OpenSkyRendering
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd

// MARK: - Melee

extension CombatAcceptanceChain: MeleeCombatWorld {
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

    /// The M15 chain carries unenchanted weapons and no effect runtime, so the
    /// fortify term is the 1 the formula reduces to for a character with none and
    /// an enchanted hit is the documented "this world cannot apply one" nil.
    /// `EnchantmentRuntimeTests` covers both paths.
    func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        1
    }

    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        nil
    }
}

// MARK: - Archery

extension CombatAcceptanceChain: ProjectileWorld {
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

    /// The M15 chain fires arrows and nothing else, so a landed spell is the
    /// documented "no effect runtime here" answer rather than a second
    /// application path this chain would never exercise.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        .none
    }

    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        ShapeSweeper.firstHit(
            query: query,
            shapes: streamer.staticCollisionCandidates(overlapping: query.bounds)
        )
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

extension CombatAcceptanceChain: RagdollWorldSeam {
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
        CombatAcceptanceWorld.stepWorld()
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

extension CombatAcceptanceChain: NoCasterCombatWorld {
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

    /// Health against the value the chain started the actor at (40), not the
    /// derived maximum (100). Dividing by the maximum would push the opponent past
    /// the flee threshold after one blow.
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
