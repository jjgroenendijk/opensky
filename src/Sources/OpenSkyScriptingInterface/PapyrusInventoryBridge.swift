import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface

/// What the item natives reach. Items are load-order FormIDs.
public protocol PapyrusInventoryBridge: AnyObject {
    func addItem(_ item: FormID, count: Int32, to holder: ReferenceKey) -> Bool
    /// Moves the items into `other` when it is not nil.
    func removeItem(
        _ item: FormID, count: Int32, from holder: ReferenceKey, to other: ReferenceKey?
    ) -> Bool
    func removeAllItems(
        from holder: ReferenceKey, to other: ReferenceKey?, removeQuestItems: Bool
    ) -> Bool
    /// Drops up to `count` in front of the holder. Nil when nothing was dropped.
    func dropItem(_ item: FormID, count: Int32, from holder: ReferenceKey) -> ReferenceKey?
    func itemCount(_ item: FormID, in holder: ReferenceKey) -> Int32?
    /// Gives the actor one first when it holds none.
    func equipItem(_ item: FormID, on actor: ReferenceKey) -> Bool
    func unequipItem(_ item: FormID, on actor: ReferenceKey) -> Bool
    func setOutfit(_ outfit: FormID, on actor: ReferenceKey) -> Bool
    func isEquipped(_ item: FormID, on actor: ReferenceKey) -> Bool?
    /// The outer nil means no inventory; the inner nil means an empty hand.
    func equippedWeapon(on actor: ReferenceKey, leftHand: Bool) -> FormID??
    func equippedShield(on actor: ReferenceKey) -> FormID??
    func unequipAll(on actor: ReferenceKey) -> Bool
    /// Takes off what covers biped slot `slot`. False without an actor or a valid slot.
    func unequipSlot(_ slot: Int32, on actor: ReferenceKey) -> Bool
    /// Nil for a form that is no item.
    func goldValue(of item: FormID) -> Int32?
    /// The plugin inventory of `holder`, before any runtime change; nil when not resident.
    func baselineInventory(of holder: ReferenceKey) -> ReferenceInventoryState?
}
