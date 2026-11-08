public import OpenSkyActorsInterface
public import OpenSkyCombatInterface

/// What the world adapters use of `MeleeCombatState`.
public protocol MeleeCombatStatePort {
    var attackPhase: MeleeAttackPhase { get }
    var drawState: WeaponDrawState { get }
    var isChainWindowOpen: Bool { get }
    var swingID: Int { get }

    var isBlocking: Bool { get }
}
