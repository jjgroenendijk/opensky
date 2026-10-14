// The item natives: `AddItem`, `RemoveItem`, `RemoveAllItems`, `GetItemCount`
// (<https://ck.uesp.net/wiki/ObjectReference_Script>), and `EquipItem`, `UnequipItem`,
// `SetOutfit` (<https://ck.uesp.net/wiki/Actor_Script>). The app answers them through
// `PapyrusInventoryBridge`. The `abSilent` flags are ignored: no item message shows.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface

/// What the item natives reach. Items are load-order FormIDs.
@MainActor
public protocol PapyrusInventoryBridge: AnyObject {
    func addItem(_ item: FormID, count: Int32, to holder: ReferenceKey) -> Bool
    /// Moves the items into `other` when it is not nil.
    func removeItem(
        _ item: FormID, count: Int32, from holder: ReferenceKey, to other: ReferenceKey?
    ) -> Bool
    func removeAllItems(from holder: ReferenceKey, to other: ReferenceKey?) -> Bool
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
    /// Nil for a form that is no item.
    func goldValue(of item: FormID) -> Int32?
    /// The plugin inventory of `holder`, before any runtime change; nil when not resident.
    func baselineInventory(of holder: ReferenceKey) -> ReferenceInventoryState?
}

extension PapyrusNativeFunctions {
    public static func installInventory(into registry: inout PapyrusNativeRegistry) {
        // A call on an `Actor` variable looks the native up under `Actor`.
        for script in ["ObjectReference", "Actor"] {
            withItem(script, "AddItem", into: &registry) { call, _, bridge, holder, item in
                let count = integer(call, at: 1) ?? 1
                return bridge.addItem(item, count: count, to: holder)
                    ? .returned(.none) : failure(call, "AddItem could not add the item")
            }
            withItem(script, "RemoveItem", into: &registry) { call, world, bridge, holder, item in
                let count = integer(call, at: 1) ?? 1
                let other = objectArgument(call, at: 3).flatMap { world.referenceKey(for: $0) }
                return bridge.removeItem(item, count: count, from: holder, to: other)
                    ? .returned(.none) : failure(call, "RemoveItem could not remove the item")
            }
            withItem(script, "GetItemCount", into: &registry) { call, _, bridge, holder, item in
                guard let count = bridge.itemCount(item, in: holder) else {
                    return failure(call, "GetItemCount needs an inventory")
                }
                return .returned(.integer(count))
            }
            installRemoveAllItems(on: script, into: &registry)
        }
        withItem("Actor", "EquipItem", into: &registry) { call, _, bridge, actor, item in
            bridge.equipItem(item, on: actor)
                ? .returned(.none) : failure(call, "EquipItem could not equip the item")
        }
        withItem("Actor", "UnequipItem", into: &registry) { call, _, bridge, actor, item in
            bridge.unequipItem(item, on: actor)
                ? .returned(.none) : failure(call, "UnequipItem needs an inventory")
        }
        withItem("Actor", "IsEquipped", into: &registry) { call, _, bridge, actor, item in
            guard let equipped = bridge.isEquipped(item, on: actor) else {
                return failure(call, "IsEquipped needs an inventory")
            }
            return .returned(.boolean(equipped))
        }
        installEquipmentReads(into: &registry)
        // `int GetGoldValue()` on any form: -1 when it has no value
        // (<https://ck.uesp.net/wiki/GetGoldValue_-_Form>).
        registry.register(PapyrusNativeFunction(
            scriptName: "Form", functionName: "GetGoldValue"
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.inventory,
                case let .plugin(plugin, objectID)? = call.receiver
                    .flatMap(world.referenceKey(for:)),
                let item = world.formIDResolver?.localFormID(
                    of: ResolvedFormID(plugin: plugin, objectID: objectID)
                )
            else { return failure(call, "GetGoldValue needs the inventory bridge and a form") }
            return .returned(.integer(bridge.goldValue(of: item) ?? -1))
        })
        // Sleep outfits are not modelled, so `abSleepOutfit` changes nothing.
        withItem("Actor", "SetOutfit", into: &registry) { call, _, bridge, actor, outfit in
            if boolean(call, at: 1, default: false) {
                return .returned(.none)
            }
            return bridge.setOutfit(outfit, on: actor)
                ? .returned(.none) : failure(call, "SetOutfit needs an outfit and an actor")
        }
    }

    /// `GetEquippedWeapon(bool abLeftHand = false)`, `GetEquippedShield()`, and
    /// `UnequipAll()`, which take no item argument.
    private static func installEquipmentReads(into registry: inout PapyrusNativeRegistry) {
        let reads: [(String, @MainActor (
            PapyrusNativeCall,
            any PapyrusInventoryBridge,
            ReferenceKey
        ) -> FormID??)] = [
            ("GetEquippedWeapon", { call, bridge, actor in
                bridge.equippedWeapon(on: actor, leftHand: boolean(call, at: 0, default: false))
            }),
            ("GetEquippedShield", { _, bridge, actor in bridge.equippedShield(on: actor) })
        ]
        for (name, read) in reads {
            withHolder("Actor", name, into: &registry) { call, world, bridge, actor in
                guard let item = read(call, bridge, actor) else {
                    return failure(call, "\(name) needs an inventory")
                }
                return .returned(item.map { formHandle($0, in: world) } ?? .none)
            }
        }
        withHolder("Actor", "UnequipAll", into: &registry) { call, _, bridge, actor in
            bridge.unequipAll(on: actor) ? .returned(.none) : failure(
                call,
                "UnequipAll needs an inventory"
            )
        }
    }

    /// A load-order FormID as a form handle, or `None` when the session cannot name it.
    static func formHandle(_ item: FormID, in world: PapyrusWorldStateBridge) -> PapyrusValue {
        guard
            let resolved = world.formIDResolver?.resolve(item),
            let handle = world.objectHandle(for: ReferenceKey(resolved: resolved))
        else { return .none }
        return .object(handle)
    }

    /// Registers a native whose receiver holds items and that takes no item.
    private static func withHolder(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, any PapyrusInventoryBridge, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script, functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.inventory,
                let receiver = call.receiver, let holder = world.referenceKey(for: receiver)
            else { return failure(call, "\(name) needs the inventory bridge and a reference") }
            return body(call, world, bridge, holder)
        })
    }

    /// `RemoveAllItems(ObjectReference akTransferTo, bool abKeepOwnership,
    /// bool abRemoveQuestItems)`. Quest items are not tracked, so all leave.
    private static func installRemoveAllItems(
        on script: String, into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script, functionName: "RemoveAllItems"
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.inventory,
                let receiver = call.receiver, let holder = world.referenceKey(for: receiver)
            else { return failure(call, "RemoveAllItems needs the inventory bridge") }
            let other = objectArgument(call, at: 0).flatMap { world.referenceKey(for: $0) }
            _ = bridge.removeAllItems(from: holder, to: other)
            return .returned(.none)
        })
    }

    /// Registers a native whose receiver holds items and whose argument 0 is the item.
    private static func withItem(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, any PapyrusInventoryBridge,
            ReferenceKey, FormID
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: script, functionName: name
        ) { call, context in
            guard
                let world = context.world as? PapyrusWorldStateBridge,
                let bridge = world.inventory,
                let receiver = call.receiver, let holder = world.referenceKey(for: receiver)
            else { return failure(call, "\(name) needs the inventory bridge and a reference") }
            guard
                let handle = objectArgument(call, at: 0),
                case let .plugin(plugin, objectID)? = world.referenceKey(for: handle),
                let item = world.formIDResolver?.localFormID(
                    of: ResolvedFormID(plugin: plugin, objectID: objectID)
                )
            else { return failure(call, "\(name) needs an item") }
            return body(call, world, bridge, holder, item)
        })
    }
}
