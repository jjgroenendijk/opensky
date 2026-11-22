// The distances and times of NPC social behaviour that no game setting holds.
// docs/engine/random-conversations.md#settings.

import Foundation

/// The fixed distances and times of the social pass that no game setting holds.
nonisolated public enum SocialLimits {
    /// Both actors of a conversation are this close to the player.
    public static let playerDistance: Float = 3000
    /// Indoors, the pair's height difference is below this.
    public static let interiorHeight: Float = 90
    /// How often an actor forgets its recent partners.
    public static let recentPartnerSeconds: Double = 120
    /// How long a pair whose quest started waits for the quest's scene to take the
    /// speaker. OpenSky's guard; the game has no timer here
    /// (docs/engine/unverified-values.md).
    public static let answerSeconds: Double = 2
    /// How long a `DialogueActivate` package waits for a quest to answer its `ADIA`.
    public static let dialogueActivateAnswerSeconds: Double = 20
    /// The speaker stops this close to the partner.
    public static let stopDistance: Float = 170
    /// A larger height difference adds `heightAllowance` to the stop distance.
    public static let heightAllowance: Float = 20
    /// The scene's trigger distance when the speaker sees the partner.
    public static let seenTriggerDistance: Float = 500
    /// The speaker paths again when its goal is this far from the partner.
    public static let repathDistance: Float = 100
    /// A speaker that moved less than `rewalkDistance` in this time is asked to walk
    /// again: a walk asked during a seat's exit clip is refused.
    public static let rewalkSeconds: Double = 1
    public static let rewalkDistance: Float = 8
    /// How far an actor reacts to a body, and says its line.
    public static let bodyDistance: Float = 400
    /// How long a checked body waits before another actor reacts to it.
    public static let bodySeconds: Double = 20
    /// The finder walks this close to the body before its line.
    public static let bodyArriveDistance: Float = 100
    /// How long a finder may walk to its body. OpenSky's guard against a body it
    /// cannot reach (docs/engine/unverified-values.md).
    public static let finderWalkSeconds: Double = 30
    /// Seconds between two detection reactions: a new watcher, a new finder. OpenSky's
    /// choice inside the game's 1 to 2 s detection pass (docs/engine/detection.md).
    public static let reactionSeconds: Double = 1
    /// Watching ends this far from the fight's centre, and no watch starts farther.
    public static let watchDistance: Float = 2000
    /// How far a melee fighter and a ranged fighter widen the fight area.
    public static let meleeThreatDistance: Float = 512
    public static let rangedThreatDistance: Float = 256
    /// A watcher refreshes a threat it detects this often.
    public static let threatRefreshSeconds: Double = 2
    /// Seconds between two back-off steps of a watcher.
    public static let watchStepSeconds = 1.5
    /// A watcher inside the fight radius backs off this far outside it.
    public static let watchBackOff: Float = 128
    /// Shortest time between two comments of one watcher.
    public static let commentSeconds: Double = 20
    /// The default look target: how far, how near for an NPC, the half angle for a new
    /// target, the hold time, and the check interval (docs/engine/head-tracking.md).
    public static let lookDistance: Float = 400
    public static let lookNearDistance: Float = 100
    public static let lookHalfAngle: Float = 120 * .pi / 180
    public static let lookHoldSeconds: Double = 5
    public static let lookCheckSeconds: ClosedRange<Double> = 1.0 ... 1.5
    public static let lookChecksPerPass = 10
    public static let lookPlayerDistance: Float = 2000
    /// Game units a second an actor moves to count as walking, as for a scene line.
    public static let movingSpeed: Float = 5
    /// Added to the trigger distance when the speaker sits.
    public static let seatedTriggerAllowance: Float = 20
}
