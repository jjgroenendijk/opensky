// Graph names melee binds to, quoted from the behavior census of `0_master.hkx` on this
// install (230 variables, 1,217 events), never memory, with vanilla's mixed case.
// Raised: what the player did. Observed: where the animation is (`BeginWeaponDraw`,
// `HitFrame`). `attackStop` is both (MeleeCombatState.swift).
// See docs/engine/combat-graph-names.md.

import Foundation

nonisolated public enum CombatGraphNames: Sendable {
    // MARK: - Events raised into the graph

    /// Unsheathe and sheathe. `weapequip.hkx` is the sub-behavior that runs
    /// them; both names are declared by `0_master.hkx` itself.
    public static let weaponDraw = "weaponDraw"
    public static let weaponSheathe = "weaponSheathe"
    /// The equip events `0_master.hkx` transitions on: `WeapEquip`, `Magic_Equip` and
    /// `Unequip`. No transition uses `weaponDraw`, so the engine picks the event.
    public static let weapEquip = "WeapEquip"
    public static let magicEquip = "Magic_Equip"
    public static let unequip = "Unequip"
    /// Swing start and the release that ends a held power attack. Directional power
    /// attacks (`attackPowerStartForward` and seven more) are in the census but not bound.
    public static let attackStart = "attackStart"
    public static let attackRelease = "attackRelease"
    public static let attackStop = "attackStop"
    /// Raising and dropping the guard.
    public static let blockStart = "blockStart"
    public static let blockStop = "blockStop"
    /// The stagger a landed hit inflicts, raised on the *target's* graph.
    /// `staggerbehavior.hkx` reads `staggerMagnitude` alongside it.
    public static let staggerStart = "staggerStart"
    public static let staggerStop = "staggerStop"
    /// The hit reaction for a blow that did not stagger, raised on the struck actor's
    /// graph. `recoilLargeStart` is not raised: no source gives its threshold.
    public static let recoilStart = "recoilStart"
    public static let recoilStop = "recoilStop"

    /// Every event the melee runtime raises, in the order the bridge raises
    /// edges in.
    public static let raisedEvents = [
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
    public static let beginWeaponDraw = "BeginWeaponDraw"
    public static let beginWeaponSheathe = "BeginWeaponSheathe"
    /// The graph's own "equip finished" events. Observed beside the two annotations,
    /// because five vanilla equip clips carry none.
    public static let weapEquipOut = "WeapEquip_Out"
    public static let unequipOut = "Unequip_Out"
    /// The swing's audible start, ahead of any contact.
    public static let weaponSwing = "weaponSwing"
    /// The frame before contact, which opens the hit window.
    public static let preHitFrame = "preHitFrame"
    /// The contact frame itself. This is the one that runs the sweep.
    public static let hitFrame = "HitFrame"
    /// Fired when a block absorbs a hit; `blockbehavior.hkx` plays the shield
    /// impact off it.
    public static let blockHitStart = "blockHitStart"

    /// Every event the melee state machine acts on when the graph fires it.
    public static let observedEvents = [
        beginWeaponDraw, beginWeaponSheathe,
        weapEquipOut, unequipOut,
        weaponSwing, preHitFrame, hitFrame,
        attackStart, attackStop, blockStart, blockStop,
        staggerStart, staggerStop, blockHitStart
    ]

    // MARK: - Variables

    /// Whether a swing is in progress. Bool, `0_master.hkx`.
    public static let isAttacking = "IsAttacking"
    /// Whether the guard is up. Bool.
    public static let isBlocking = "IsBlocking"
    /// Whether a stagger is playing. Bool, read by `staggerbehavior.hkx`.
    public static let isStaggering = "IsStaggering"
    /// How hard the stagger is. Real, 0...1 in vanilla authoring.
    public static let staggerMagnitude = "staggerMagnitude"
    /// Whether a hit reaction plays (bool), and how hard the blow was (real).
    public static let isRecoiling = "IsRecoiling"
    public static let recoilMagnitude = "recoilMagnitude"
    /// The WEAP `speed` multiplier the attack clips scale their rate by. Real.
    public static let weaponSpeedMult = "weaponSpeedMult"
    /// What each hand holds (`int32`), which picks the animation set in `weapequip.hkx`
    /// and `1hm_behavior.hkx`. `CombatHandType` is the encoding.
    public static let rightHandType = "iRightHandType"
    public static let leftHandType = "iLeftHandType"

    /// Every variable the melee runtime writes, in write order.
    public static let variables = [
        isAttacking, isBlocking, isStaggering,
        staggerMagnitude, weaponSpeedMult,
        rightHandType, leftHandType
    ]
}
