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
    /// How long a pair waits for a quest to answer its `ADIA` with a scene. OpenSky's
    /// choice: the story manager answers in the same frame
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
    /// How far an actor reacts to a body, and says its line.
    public static let bodyDistance: Float = 400
    /// How long a checked body waits before another actor reacts to it.
    public static let bodySeconds: Double = 20
    /// A watcher stops watching a fighter further away.
    public static let watchDistance: Float = 1000
    /// Shortest time between two comments of one watcher.
    public static let commentSeconds: Double = 20
    /// How near another NPC must be for a walker to look at it. OpenSky's choice: the
    /// head tracking notice distance (docs/engine/unverified-values.md).
    public static let lookDistance: Float = 384
    /// Game units an actor moves between passes to count as walking.
    public static let movingDistance: Float = 8
}
