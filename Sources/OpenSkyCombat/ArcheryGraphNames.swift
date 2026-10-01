// Graph names archery binds to, quoted from the behavior census of this install
// (`HKBBehaviorCensusRealDataTests`), never memory, with vanilla's mixed case. Raised
// vs observed is our direction of use. `bowReset` and `attackRelease` appear on both
// sides. `arrowRelease` is the frame the projectile spawns; no clock times it.
// See docs/engine/archery.md.

import Foundation

nonisolated public enum ArcheryGraphNames: Sendable {
    // MARK: - Events raised into the graph

    /// Begin drawing. Raised when the attack button goes down with a bow in
    /// hand, where the same press with a melee weapon raises
    /// `CombatGraphNames.attackStart`.
    public static let bowDrawStart = "bowDrawStart"
    /// Loose. Shared with melee's held power attack, which is the same button
    /// coming back up.
    public static let attackRelease = CombatGraphNames.attackRelease
    /// Abandon the draw without loosing — sheathing mid-pull, or a stagger.
    public static let bowReset = "bowReset"

    /// Every event the archery runtime raises, in the order the runtime raises
    /// edges in.
    public static let raisedEvents = [bowDrawStart, attackRelease, bowReset]

    // MARK: - Events observed coming back out

    /// The clip annotation that puts an arrow in the draw hand. This is the
    /// nock, and it is the frame the arrow becomes a visible attachment.
    public static let arrowAttach = "arrowAttach"
    /// Full draw reached. Past this the shot deals its full damage; see
    /// `ArcheryDamage`.
    public static let bowDrawn = "bowDrawn"
    /// The frame the arrow leaves the string. This is the spawn frame.
    public static let arrowRelease = "arrowRelease"
    /// The arrow leaves the hand, which is the frame its attachment is dropped.
    public static let arrowDetach = "arrowDetach"
    /// The two clip annotations that bracket the draw animation itself.
    public static let bowDraw = "BowDraw"
    public static let bowRelease = "BowRelease"

    /// Every event the archery state machine acts on when the graph fires it.
    public static let observedEvents = [
        arrowAttach, bowDrawn, arrowRelease, arrowDetach, bowReset, bowDraw, bowRelease
    ]

    // MARK: - Variables

    /// Whether the bow is at full draw. Bool, `0_master.hkx`.
    public static let isBowDrawn = "bBowDrawn"

    /// Every variable the archery runtime writes. The `iState_NPCBow*` integers are left
    /// out, because their encoding is unknown and a guess would silently pick the wrong
    /// set. Eagle Eye zoom variables are a perk effect and are not written.
    public static let variables = [isBowDrawn]
}
