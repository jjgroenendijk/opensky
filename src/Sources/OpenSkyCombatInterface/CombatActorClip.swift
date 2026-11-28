/// Which single-clip animation a fighting actor should play.
///
/// A few cases rather than a free-form clip name because NPC playback in this
/// milestone is one clip at a time (`ActorAnimationPlayback`) and the engine
/// picks which; a name would let a caller ask for something no rig carries.
nonisolated public enum CombatActorClip: String, Equatable, Sendable, CaseIterable {
    case attack
    /// A swing of the left hand's weapon.
    case leftAttack
    /// A bash with a weapon, and with a shield.
    case bash
    case shieldBash
    case stagger
    case hitReaction
}
