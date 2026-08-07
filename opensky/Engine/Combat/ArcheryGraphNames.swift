// The graph variable and event names archery binds to (issue #196, roadmap
// item 15.5).
//
// Same rule as `CombatGraphNames`, and it matters more here rather than less:
// every name below was read out of the M14 behavior census over the user's own
// install (`logs/hkx-behavior-census.log`, produced by
// `HKBBehaviorCensusRealDataTests`), never from memory. Each one is quoted
// exactly as third-person `meshes\actors\character\behaviors\0_master.hkx`
// spells it, and the census confirms all of them are declared by that file —
// which is the graph OpenSky attaches — as well as by `1hm_behavior.hkx`,
// `horsebehavior.hkx`, and the `_1stperson` copies of both.
//
// Vanilla's capitalization is not consistent and is reproduced rather than
// tidied: `arrowRelease` and `bowDrawn` are lower-camel while `BowDraw` and
// `BowRelease` are upper-camel, in the same file.
//
// The raised/observed split is the direction of travel this engine uses a name
// in, not a property of the data — Havok events have no direction. Two of them
// appear on both sides on purpose:
//
// * `bowReset` is raised when the engine cancels a draw (the bow is put away
//   mid-pull) and is also fired by the graph when the draw collapses on its
//   own, and `ArcheryState` acts on the fired one either way.
// * `attackRelease` is shared with melee, where 15.4 already names it as the
//   release that ends a held power attack. Loosing an arrow is the same
//   release, on the same button, so the name is reused rather than duplicated.
//
// `arrowRelease` is the important one: it is the frame the arrow leaves the
// string, and it is the frame `ProjectileRuntime` spawns a projectile on. The
// engine does not time a shot beside the animation for exactly the reason
// 15.4's contact frame is not timed either — a release invented from a clock
// fires at a moment the bow is not at.
//
// Documented in docs/engine/archery.md.

import Foundation

nonisolated enum ArcheryGraphNames {
    // MARK: - Events raised into the graph

    /// Begin drawing. Raised when the attack button goes down with a bow in
    /// hand, where the same press with a melee weapon raises
    /// `CombatGraphNames.attackStart`.
    static let bowDrawStart = "bowDrawStart"
    /// Loose. Shared with melee's held power attack, which is the same button
    /// coming back up.
    static let attackRelease = CombatGraphNames.attackRelease
    /// Abandon the draw without loosing — sheathing mid-pull, or a stagger.
    static let bowReset = "bowReset"

    /// Every event the archery runtime raises, in the order the runtime raises
    /// edges in.
    static let raisedEvents = [bowDrawStart, attackRelease, bowReset]

    // MARK: - Events observed coming back out

    /// The clip annotation that puts an arrow in the draw hand. This is the
    /// nock, and it is the frame the arrow becomes a visible attachment.
    static let arrowAttach = "arrowAttach"
    /// Full draw reached. Past this the shot deals its full damage; see
    /// `ArcheryDamage`.
    static let bowDrawn = "bowDrawn"
    /// The frame the arrow leaves the string. This is the spawn frame.
    static let arrowRelease = "arrowRelease"
    /// The arrow leaves the hand, which is the frame its attachment is dropped.
    static let arrowDetach = "arrowDetach"
    /// The two clip annotations that bracket the draw animation itself.
    static let bowDraw = "BowDraw"
    static let bowRelease = "BowRelease"

    /// Every event the archery state machine acts on when the graph fires it.
    static let observedEvents = [
        arrowAttach, bowDrawn, arrowRelease, arrowDetach, bowReset, bowDraw, bowRelease
    ]

    // MARK: - Variables

    /// Whether the bow is at full draw. Bool, `0_master.hkx`.
    static let isBowDrawn = "bBowDrawn"

    /// Every variable the archery runtime writes.
    ///
    /// `iState_NPCBow`, `iState_NPCBowDrawn` and `iState_NPCBowDrawnQuickShot`
    /// are deliberately absent, for the reason `CombatGraphNames` leaves
    /// `iRightHandType` absent: the census gives their names and their `int32`
    /// type and nothing states the encoding, so a guessed integer would select
    /// an animation set silently rather than visibly. `bowZoom`, `bowZoomAmt`
    /// and `bAimActive` are absent because Eagle Eye zoom is a perk effect and
    /// perks are M18's.
    static let variables = [isBowDrawn]
}
