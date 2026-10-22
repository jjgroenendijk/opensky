// What a death leaves besides the fall: the killing hit's push, the dropped weapon, a
// severed head, and the removal of old bodies. The game settings are in `DeathSettings`;
// the uses are OpenSky's reading (docs/engine/ragdoll.md#death-effects).

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// How many of each death effect happened since the session started, for the panel.
nonisolated public struct DeathEffectCounts: Equatable, Sendable {
    public var pushedBodies = 0
    public var droppedWeapons = 0
    public var dismemberments = 0
    public var removedBodies = 0

    public init() {}

    public var readout: String {
        "Death effects: \(pushedBodies) pushed · \(droppedWeapons) weapons dropped · "
            + "\(dismemberments) dismembered · \(removedBodies) bodies removed"
    }
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

    private func source(of hit: CombatHitRecord) -> SIMD3<Float>? {
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
        if deathRandom.percent() < deathSettings.dropWeaponChance {
            let nodes = world.dropWeapon(of: key)
            if !nodes.isEmpty {
                hiddenNodes[key, default: []].formUnion(nodes)
                deathEffects.droppedWeapons += 1
            }
        }
        if hit?.canSever == true, deathRandom.percent() < deathSettings.dismemberChance {
            dismember(key)
        }
    }

    /// Cuts off `key`'s head. The node is kept with the death, so the body stays
    /// headless after a save.
    /// - Returns: false for a living actor, one already cut, or one with no head part.
    @discardableResult
    public func dismember(_ key: ReferenceKey) -> Bool {
        guard
            let state = store.component(ActorDeathState.self, for: key), state.isDead,
            state.severedNode == nil,
            let node = world.severableNode(of: key),
            let pose = world.ragdollPose(of: key)
        else { return false }
        var cut = state
        cut.severedNode = node
        store.set(cut, for: key, in: pose.cell)
        let local = (world.animatedPose(of: key)?[node] ?? matrix_identity_float4x4).columns.3
        let position = pose.actorToWorld * local
        world.showDismemberment(
            of: key, node: node, at: SIMD3(position.x, position.y, position.z)
        )
        deathEffects.dismemberments += 1
        return true
    }

    /// The panel's control: kills the selected actor when it lives, then cuts.
    @discardableResult
    public func dismemberSelected() -> Bool {
        guard let runtime, let key = world.selectedRagdollActor else { return false }
        if !runtime.isDead(key) {
            runtime.trigger(key)
        }
        return dismember(key)
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
            hiddenNodes[key] = nil
            deathEffects.removedBodies += 1
        }
    }

    /// The nodes to hide on each resident body: a dropped weapon's and a cut head's.
    func hiddenNodesByResident() -> [ReferenceKey: Set<String>] {
        var hidden = hiddenNodes
        for resident in world.ragdollResidents {
            if let node = store.component(ActorDeathState.self, for: resident.key)?.severedNode {
                hidden[resident.key, default: []].insert(node)
            }
        }
        return hidden.filter { !$0.value.isEmpty }
    }

    /// Lays the hidden nodes over `poses`, each one shrunk to a point with its children.
    func hidePoseNodes(
        _ hidden: [ReferenceKey: Set<String>], in poses: inout [UInt32: [String: float4x4]]
    ) {
        for (key, nodes) in hidden {
            guard let pose = world.ragdollPose(of: key), let animated = world.animatedPose(of: key)
            else { continue }
            let reference = pose.reference.rawValue
            let current = animated.merging(poses[reference] ?? [:]) { _, simulated in simulated }
            let collapsed = PoseNodeHiding.collapsed(
                nodes,
                names: pose.skeleton.boneNames,
                parents: pose.skeleton.parentIndices,
                pose: current
            )
            guard !collapsed.isEmpty else { continue }
            poses[reference, default: [:]].merge(collapsed) { _, hiddenMatrix in hiddenMatrix }
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

/// Hides skeleton nodes by shrinking each one, and every bone under it, to the node's
/// origin. Skinned vertices on those bones fold into one point, so the part vanishes.
nonisolated public enum PoseNodeHiding {
    public static func collapsed(
        _ nodes: Set<String>,
        names: [String],
        parents: [Int],
        pose: [String: float4x4]
    ) -> [String: float4x4] {
        var anchors: [Int?] = Array(repeating: nil, count: names.count)
        var resolved = Array(repeating: false, count: names.count)
        func anchor(of index: Int, depth: Int) -> Int? {
            guard depth <= names.count else { return nil }
            if resolved[index] {
                return anchors[index]
            }
            let parent = parents.indices.contains(index) ? parents[index] : -1
            let found = nodes.contains(names[index]) ? index
                : names.indices.contains(parent) ? anchor(of: parent, depth: depth + 1) : nil
            anchors[index] = found
            resolved[index] = true
            return found
        }
        var result: [String: float4x4] = [:]
        for index in names.indices {
            guard let root = anchor(of: index, depth: 0), let matrix = pose[names[root]] else {
                continue
            }
            result[names[index]] = float4x4(columns: (.zero, .zero, .zero, matrix.columns.3))
        }
        return result
    }
}
