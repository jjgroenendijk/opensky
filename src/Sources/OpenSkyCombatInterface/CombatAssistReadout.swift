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

    /// The attack an NPC's pick chose for its swing in progress.
    public struct AttackPick: Equatable, Sendable {
        public var attacker: ReferenceKey
        /// The `ATKE` event, such as `attackPowerStart_Forward`.
        public var event: String
        public var isPowerAttack: Bool
        public var knockdown: Float

        public init(attacker: ReferenceKey, event: String, isPowerAttack: Bool, knockdown: Float) {
            self.attacker = attacker
            self.event = event
            self.isPowerAttack = isPowerAttack
            self.knockdown = knockdown
        }
    }

    public var tracks: [Track] = []
    public var attackPicks: [AttackPick] = []
    /// The target the player's last shot turned toward. Nil when it turned to none.
    public var autoAim: ProjectileAimPick?
    public var threats: [DangerThreat] = []
    public var watches: [ReferenceKey: CombatDangerWatch] = [:]
    /// The last hits and their reactions, oldest first.
    public var reactions: [HitReactionReport] = []

    public init() {}
}
