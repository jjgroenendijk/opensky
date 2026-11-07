// What a death leaves besides the fall: the killing hit's push, the dropped weapon, a
// severed head, and the removal of old bodies. The game settings are in `DeathSettings`;
// the uses are OpenSky's reading (docs/engine/ragdoll.md#death-effects).

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// How many of each death effect happened since the session started, for the readout.
nonisolated public struct DeathEffectCounts: Equatable, Sendable {
    public var pushedBodies = 0
    public var droppedWeapons = 0
    public var dismemberments = 0
    public var removedBodies = 0

    public init() {}
}

extension RagdollCoordinator {
    /// A hit older than this did not kill, so a later death from bleeding or a fall
    /// pushes nothing. OpenSky's number.
    static let hitWindowSeconds: Float = 2
    /// The push leans up by this share, so a body lifts a little as it falls back.
    static let impulseLift: Float = 0.25

    /// Keeps `hit` as `key`'s last hit, for the death it may cause this frame.
    public func noteHit(_ hit: CombatHitRecord, on key: ReferenceKey) {
        recentHits[key] = (hit, clock)
    }

    func recentHit(on key: ReferenceKey) -> CombatHitRecord? {
        guard let entry = recentHits[key], clock - entry.time <= Self.hitWindowSeconds
        else { return nil }
        return entry.hit
    }

    /// The killing hit's push: its force, away from where it came from.
    func impulse(of hit: CombatHitRecord, on resident: RagdollResident) -> SIMD3<Float> {
        let force = deathSettings.force(of: hit)
        guard force > 0, let source = source(of: hit) else { return .zero }
        let away = resident.position - source
        let flat = SIMD2(away.x, away.y)
        guard simd_length_squared(flat) > 1e-6 else { return SIMD3(0, 0, force) }
        let direction = simd_normalize(SIMD3(simd_normalize(flat), Self.impulseLift))
        deathEffects.pushedBodies += 1
        return direction * force
    }

    func source(of hit: CombatHitRecord) -> SIMD3<Float>? {
        if let origin = hit.origin {
            return origin
        }
        guard let attacker = hit.attacker else { return nil }
        if attacker == .player {
            return world.playerFeetPosition
        }
        return world.ragdollResidents.first { $0.key == attacker }?.position
    }

    /// The rolls at the moment of death: the weapon falls, and a qualifying blow cuts.
    func applyDeathEffects(of hit: CombatHitRecord?, to key: ReferenceKey) {
        if deathRandom.percent() < deathSettings.dropWeaponChance, world.dropWeapon(of: key) {
            deathEffects.droppedWeapons += 1
        }
        if hit?.canSever == true, deathRandom.percent() < deathSettings.dismemberChance {
            dismember(key)
        }
    }

    /// Cuts off `key`'s head. The node is kept with the death, so the body stays
    /// headless after a save; the cell rebuild draws the body and the head apart.
    /// - Returns: false for a living actor, one already cut, or one with no head part.
    @discardableResult
    public func dismember(_ key: ReferenceKey) -> Bool {
        guard
            let state = store.component(ActorDeathState.self, for: key), state.isDead,
            state.severedNode == nil,
            let node = world.severableNode(of: key),
            let pose = world.ragdollPose(of: key)
        else { return false }
        let drawn = drawnPose(of: key, pose: pose)
        var cut = state
        cut.severedNode = node
        store.set(cut, for: key, in: pose.cell)
        let local = (drawn[node] ?? matrix_identity_float4x4).columns.3
        let world4 = pose.actorToWorld * local
        let position = SIMD3(world4.x, world4.y, world4.z)
        world.showDismemberment(of: key, node: node, at: position)
        let blow = recentHit(on: key).flatMap(source(of:)).map { position - $0 }
        severedHeads[key] = SeveredHead(
            key: key, cell: pose.cell, node: node, pose: drawn,
            actorToWorld: pose.actorToWorld, away: blow ?? .zero
        )
        deathEffects.dismemberments += 1
        return true
    }

    /// The pose `key` is drawn in now: the clip's, with the ragdoll's bones laid over it
    /// and their children carried along. A head cut from a fallen body starts at its neck.
    func drawnPose(of key: ReferenceKey, pose: RagdollActorPose) -> [String: float4x4] {
        let animated = world.animatedPose(of: key) ?? [:]
        let live = runtime?.world.ragdolls.first { $0.key == key }?.instance
        guard
            let simulated = live?.blendedBoneMatrices(
                animated: animated, worldToActor: pose.actorToWorld.inverse
            ) ?? drawnRagdollBones[key]
        else { return animated }
        let names = pose.skeleton.bones.map(\.name)
        let base = SkeletonPose(
            bones: SkeletonBoneIndex(names: names),
            matrices: names.map { animated[$0] ?? matrix_identity_float4x4 }
        )
        let posed = base.overriding(simulated, parents: pose.skeleton.parentIndices).named
        return animated.merging(posed) { _, drawn in drawn }
    }

    /// Steps every head, and keeps where a head came to rest in its body's death state.
    func advanceSeveredHeads(by delta: Float) {
        let step = world.ragdollStepWorld
        for key in severedHeads.keys.sorted() {
            guard var head = severedHeads[key] else { continue }
            head.advance(by: delta, world: step)
            if
                head.body.isSleeping, !head.isRestRecorded,
                var state = store.component(ActorDeathState.self, for: key)
            {
                state.severedHeadRest = head.restTransform
                store.set(state, for: key, in: head.body.placingCell)
                head.isRestRecorded = true
            }
            severedHeads[key] = head
        }
    }

    /// The pose of every resident cut head. A cut body that loads with no head in flight,
    /// as after a save, drops its head where the neck is. A head stays while its cell
    /// is resident and its body is cut, even through a frame its body has no pose.
    func severedHeadPoses() -> [UInt32: [String: float4x4]] {
        let cells = world.residentRagdollCells
        severedHeads = severedHeads.filter { key, head in
            cells.contains(head.body.placingCell)
                && store.component(ActorDeathState.self, for: key)?.severedNode != nil
        }
        var poses: [UInt32: [String: float4x4]] = [:]
        for resident in world.ragdollResidents {
            let key = resident.key
            let state = store.component(ActorDeathState.self, for: key)
            guard
                let node = state?.severedNode,
                let pose = world.ragdollPose(of: key),
                let head = severedHeads[key] ?? SeveredHead(
                    key: key, cell: pose.cell, node: node,
                    pose: drawnPose(of: key, pose: pose),
                    actorToWorld: pose.actorToWorld, rest: state?.severedHeadRest
                )
            else { continue }
            severedHeads[key] = head
            poses[pose.reference.rawValue] = head.bonePose(actorToWorld: pose.actorToWorld)
        }
        return poses
    }

    /// With more dead loaded than `iRemoveExcessDeadCount`, the oldest bodies no quest
    /// keeps go once they have been dead `fRemoveExcessDeadTime`.
    func removeExcessDead(runtime: RagdollRuntime) {
        let dead = world.ragdollResidents.map(\.key).filter(runtime.isDead)
        for key in dead where deathTimes[key] == nil {
            deathTimes[key] = clock
        }
        let removals = ExcessDeadRule.removals(
            dead: dead.map { ($0, deathTimes[$0] ?? clock) },
            kept: world.isCorpseKept,
            now: clock,
            settings: deathSettings
        )
        for key in removals {
            world.removeCorpse(key)
            runtime.removeRagdoll(key)
            deathTimes[key] = nil
            recentHits[key] = nil
            severedHeads[key] = nil
            drawnRagdollBones[key] = nil
            deathEffects.removedBodies += 1
        }
    }
}

/// Which bodies the excess-dead rule removes. Pure, so a test can drive it.
nonisolated public enum ExcessDeadRule {
    public static func removals(
        dead: [(key: ReferenceKey, diedAt: Float)],
        kept: (ReferenceKey) -> Bool,
        now: Float,
        settings: DeathSettings
    ) -> [ReferenceKey] {
        let limit = max(settings.excessDeadCount, 0)
        guard dead.count > limit else { return [] }
        let oldest = dead.filter { !kept($0.key) }.sorted { $0.diedAt < $1.diedAt }
        return oldest.prefix(dead.count - limit)
            .filter { now - $0.diedAt >= settings.excessDeadSeconds }
            .map(\.key)
    }
}
