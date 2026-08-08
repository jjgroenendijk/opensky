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
    /// The equip events `0_master.hkx` actually transitions on (issue #403).
    ///
    /// `weaponDraw` above is declared by the graph but named by no transition
    /// in any file under `meshes\actors\character\behaviors\`, which is why
    /// raising it alone moved nothing: in vanilla the engine decides *what* is
    /// being drawn and raises the matching equip event. `Default_Behavior` in
    /// `0_master.hkx` carries `MT_Behavior_State -[WeapEquip]-> Weap_Equip_State`,
    /// `-[Magic_Equip]-> Magic_Equip_State`, and `Weap_Readied_State -[Unequip]->
    /// Weap_Unequip_State`, so these three are the ones that move the graph.
    static let weapEquip = "WeapEquip"
    static let magicEquip = "Magic_Equip"
    static let unequip = "Unequip"
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
    /// The hit reaction a blow that did not stagger produces, raised on the
    /// graph of whoever was struck (issue #374).
    ///
    /// Read out of the same census as everything else here: the third-person
    /// `0_master.hkx` declares `recoilStart`, `recoilStop` and
    /// `recoilLargeStart` as events, and `IsRecoiling : bool` and
    /// `recoilMagnitude : real` as variables. `recoilLargeStart` is the heavier
    /// variant and is left unraised — which magnitude selects it is a threshold
    /// no open source states, and guessing it would play the wrong reaction.
    static let recoilStart = "recoilStart"
    static let recoilStop = "recoilStop"

    /// Every event the melee runtime raises, in the order the bridge raises
    /// edges in.
    static let raisedEvents = [
        weaponDraw, weaponSheathe,
        weapEquip, magicEquip, unequip,
        attackStart, attackRelease, attackStop,
        blockStart, blockStop,
        staggerStart, staggerStop,
        recoilStart, recoilStop
    ]

    // MARK: - Events observed coming back out

    /// The clip annotations that mark the frame the weapon leaves the sheathed
    /// node for the hand and the frame it goes back. The attachment moves on
    /// these rather than on the raised event, so the model changes nodes at the
    /// animation's own phase instead of at the key press.
    static let beginWeaponDraw = "BeginWeaponDraw"
    static let beginWeaponSheathe = "BeginWeaponSheathe"
    /// The graph's own answer that the equip finished: the events
    /// `0_master.hkx` transitions into `Weap_Readied_State` and back out of
    /// `Weap_Unequip_State` on. Observed alongside the two annotations above,
    /// because five of the vanilla equip clips carry no annotation (issue #403).
    static let weapEquipOut = "WeapEquip_Out"
    static let unequipOut = "Unequip_Out"
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
        weapEquipOut, unequipOut,
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
    /// Whether a hit reaction is playing, and how hard the blow was. Bool and
    /// real, both declared by `0_master.hkx` beside the `recoilStart` event
    /// (issue #374).
    static let isRecoiling = "IsRecoiling"
    static let recoilMagnitude = "recoilMagnitude"
    /// The WEAP `speed` multiplier the attack clips scale their rate by. Real.
    static let weaponSpeedMult = "weaponSpeedMult"
    /// What each hand is holding, `int32`. These pick the animation set: the
    /// equip selectors in `weapequip.hkx` index their child list straight off
    /// them, and most of the combat transitions in `1hm_behavior.hkx` are
    /// conditioned on them. `CombatHandType` is the encoding and records where
    /// it was read from (issue #403).
    static let rightHandType = "iRightHandType"
    static let leftHandType = "iLeftHandType"

    /// Every variable the melee runtime writes, in write order.
    static let variables = [
        isAttacking, isBlocking, isStaggering,
        staggerMagnitude, weaponSpeedMult,
        rightHandType, leftHandType
    ]
}
