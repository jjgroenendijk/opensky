public import OpenSkyActorsInterface
public import OpenSkyCombatInterface

/// What the world adapters use of `MeleeCombatRuntime`.
public protocol MeleeCombatRuntimePort: AnyObject {
    associatedtype MeleeCombatState: MeleeCombatStatePort
    var state: MeleeCombatState { get }
    var strikeKind: MeleeStrikeKind { get }
    var weapon: MeleeWeaponProfile { get set }

    var offHand: CombatHandType { get set }
}
