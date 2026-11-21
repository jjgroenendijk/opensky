// What `state assist` shows of the combat helper rules: attack tracking, projectile
// auto-aim, danger avoidance, and hit reactions. docs/engine/combat-assist.md.

public import OpenSkyFormatsESM
import simd

nonisolated public struct CombatAssistReadout: Equatable, Sendable {
    /// One attacker that faces its aim through a melee attack.
    public struct Track: Equatable, Sendable {
        public var attacker: ReferenceKey
        public var target: ReferenceKey
        public var aim: SIMD3<Float>
        public var refreshes: Int

        public init(
            attacker: ReferenceKey,
            target: ReferenceKey,
            aim: SIMD3<Float>,
            refreshes: Int
        ) {
            self.attacker = attacker
            self.target = target
            self.aim = aim
            self.refreshes = refreshes
        }
    }

    public var tracks: [Track] = []
    /// The target the player's last shot turned toward. Nil when it turned to none.
    public var autoAim: ProjectileAimPick?
    public var threats: [DangerThreat] = []
    public var watches: [ReferenceKey: CombatDangerWatch] = [:]
    /// The last hits and their reactions, oldest first.
    public var reactions: [HitReactionReport] = []

    public init() {}
}
