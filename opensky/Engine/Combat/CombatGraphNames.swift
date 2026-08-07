// The graph variable and event names melee combat binds to (issue #195,
// roadmap item 15.4).
//
// Every name here was read out of the M14 behavior census over the user's own
// install (`logs/hkx-behavior-census.log`, produced by
// `HKBBehaviorCensusRealDataTests`), never from memory. `0_master.hkx` declares
// 230 variables and 1,217 events and a merely plausible name resolves to
// nothing at all, so each constant below is quoted exactly as the third-person
// `meshes\actors\character\behaviors\0_master.hkx` spells it, including the
// inconsistent capitalization vanilla actually uses: `attackStart` is
// lower-camel and `HitFrame` is upper-camel, in the same file.
//
// The split between `raisedEvents` and `observedEvents` is the direction of
// travel, not a property of the data. Havok events have no direction — the same
// name can be raised into a graph and fired back out of it — so the two lists
// record which side of the seam this engine uses each name on:
//
// * Raised: the engine tells the graph what the player did. Draw, sheath,
//   attack, block, and the stagger a landed hit inflicts on its target.
// * Observed: the graph tells the engine where in the animation it now is.
//   `BeginWeaponDraw` and `BeginWeaponSheathe` are the clip annotations that
//   mark the frame the weapon actually changes hands, and `preHitFrame` and
//   `HitFrame` bracket the window a swing can connect in.
//
// A name appearing in both lists is not a contradiction: `attackStop` is raised
// when the player lets go and is also fired by the graph when the attack state
// ends on its own, and the melee state machine acts on the fired one either way
// (see MeleeCombatState.swift).
//
// Documented in docs/engine/melee-combat.md.

import Foundation

nonisolated enum CombatGraphNames {
    // MARK: - Events raised into the graph

    /// Unsheathe and sheathe. `weapequip.hkx` is the sub-behavior that runs
    /// them; both names are declared by `0_master.hkx` itself.
    static let weaponDraw = "weaponDraw"
    static let weaponSheathe = "weaponSheathe"
    /// Swing start and the release that ends a held power attack. Power-attack
    /// direction variants (`attackPowerStartForward` and its seven siblings)
    /// exist in the census and are M18's, not this item's.
    static let attackStart = "attackStart"
    static let attackRelease = "attackRelease"
    static let attackStop = "attackStop"
    /// Raising and dropping the guard.
    static let blockStart = "blockStart"
    static let blockStop = "blockStop"
    /// The stagger a landed hit inflicts, raised on the *target's* graph.
    /// `staggerbehavior.hkx` reads `staggerMagnitude` alongside it.
    static let staggerStart = "staggerStart"
    static let staggerStop = "staggerStop"

    /// Every event the melee runtime raises, in the order the bridge raises
    /// edges in.
    static let raisedEvents = [
        weaponDraw, weaponSheathe,
        attackStart, attackRelease, attackStop,
        blockStart, blockStop,
        staggerStart, staggerStop
    ]

    // MARK: - Events observed coming back out

    /// The clip annotations that mark the frame the weapon leaves the sheathed
    /// node for the hand and the frame it goes back. The attachment moves on
    /// these rather than on the raised event, so the model changes nodes at the
    /// animation's own phase instead of at the key press.
    static let beginWeaponDraw = "BeginWeaponDraw"
    static let beginWeaponSheathe = "BeginWeaponSheathe"
    /// The swing's audible start, ahead of any contact.
    static let weaponSwing = "weaponSwing"
    /// The frame before contact, which opens the hit window.
    static let preHitFrame = "preHitFrame"
    /// The contact frame itself. This is the one that runs the sweep.
    static let hitFrame = "HitFrame"
    /// Fired when a block absorbs a hit; `blockbehavior.hkx` plays the shield
    /// impact off it.
    static let blockHitStart = "blockHitStart"

    /// Every event the melee state machine acts on when the graph fires it.
    static let observedEvents = [
        beginWeaponDraw, beginWeaponSheathe,
        weaponSwing, preHitFrame, hitFrame,
        attackStart, attackStop, blockStart, blockStop,
        staggerStart, staggerStop, blockHitStart
    ]

    // MARK: - Variables

    /// Whether a swing is in progress. Bool, `0_master.hkx`.
    static let isAttacking = "IsAttacking"
    /// Whether the guard is up. Bool.
    static let isBlocking = "IsBlocking"
    /// Whether a stagger is playing. Bool, read by `staggerbehavior.hkx`.
    static let isStaggering = "IsStaggering"
    /// How hard the stagger is. Real, 0...1 in vanilla authoring.
    static let staggerMagnitude = "staggerMagnitude"
    /// The WEAP `speed` multiplier the attack clips scale their rate by. Real.
    static let weaponSpeedMult = "weaponSpeedMult"

    /// Every variable the melee runtime writes, in write order.
    ///
    /// `iRightHandType` and `iLeftHandType` are deliberately absent. The
    /// census gives their names and their `int32` type but not the encoding —
    /// which integer means "one-handed sword" is a mapping no open source
    /// consulted here states, and guessing it would silently select the wrong
    /// attack animation set. They stay unwritten until a probe settles the
    /// encoding, which leaves the graph on its own defaults rather than on a
    /// wrong number.
    static let variables = [
        isAttacking, isBlocking, isStaggering,
        staggerMagnitude, weaponSpeedMult
    ]
}
