// `AddInventoryEventFilter(Form)`, `RemoveInventoryEventFilter(Form)`, and
// `RemoveAllInventoryEventFilters()`
// (<https://ck.uesp.net/wiki/AddInventoryEventFilter_-_ObjectReference>).
// Once a script has a filter, it only hears `OnItemAdded` and `OnItemRemoved` for an item
// a filter names, directly or through a form list. Filters live in the holder's script
// state, one form link per script and form, so they survive a save.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installInventoryFilters(into registry: inout PapyrusNativeRegistry) {
        for script in ["ObjectReference", "Actor", "ReferenceAlias"] {
            withFilteredInstances(
                script,
                "AddInventoryEventFilter",
                into: &registry
            ) { call, bridge, key in
                guard let filter = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                else { return false }
                bridge.updateScriptedState(of: key.reference) {
                    $0.setForm(PapyrusWorldStateBridge.inventoryFilterName(key, filter), filter)
                }
                return true
            }
            withFilteredInstances(
                script,
                "RemoveInventoryEventFilter",
                into: &registry
            ) { call, bridge, key in
                guard let filter = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                else { return false }
                bridge.updateScriptedState(of: key.reference) {
                    $0.setForm(PapyrusWorldStateBridge.inventoryFilterName(key, filter), nil)
                }
                return true
            }
            withFilteredInstances(
                script,
                "RemoveAllInventoryEventFilters",
                into: &registry
            ) { _, bridge, key in
                let prefix = PapyrusWorldStateBridge.inventoryFilterPrefix(key)
                bridge.updateScriptedState(of: key.reference) { state in
                    for name in state.forms.keys where name.hasPrefix(prefix) {
                        state.setForm(name, nil)
                    }
                }
                return true
            }
        }
    }

    /// Registers a native that changes the filters of each script instance the receiver
    /// names: `Self`, an alias slot, or a reference with every script on it.
    private static func withFilteredInstances(
        _ script: String, _ name: String, into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, PapyrusInstanceKey
        ) -> Bool
    ) {
        registry
            .register(PapyrusNativeFunction(
                scriptName: script,
                functionName: name
            ) { call, context in
                guard
                    let bridge = context.world as? PapyrusWorldStateBridge,
                    let world = bridge.world,
                    let receiver = call.receiver
                else { return failure(call, "\(name) needs a world and a receiver") }
                let keys = filteredInstances(of: receiver, in: world, bridge: bridge)
                for key in keys where !body(call, bridge, key) {
                    return failure(call, "\(name) needs a form")
                }
                return .returned(.none)
            })
    }

    private static func filteredInstances(
        of handle: PapyrusObjectHandle, in world: PapyrusWorldRuntime,
        bridge: PapyrusWorldStateBridge
    ) -> [PapyrusInstanceKey] {
        if let key = world.keysByHandle[handle] {
            return [key]
        }
        if let slot = world.aliasSlot(for: handle) {
            return world.aliasSlotsByInstance.filter { $0.value == slot }.keys.sorted()
        }
        return bridge.referenceKey(for: handle).map(world.instanceKeys(on:)) ?? []
    }
}

extension PapyrusWorldStateBridge {
    static func inventoryFilterPrefix(_ key: PapyrusInstanceKey) -> String {
        "inventoryfilter:\(key.scriptName):"
    }

    static func inventoryFilterName(_ key: PapyrusInstanceKey, _ filter: ReferenceKey) -> String {
        inventoryFilterPrefix(key) + "\(filter)"
    }

    /// True when the instance has no filter, or a filter names `item` or holds it in a list.
    func passesInventoryFilters(_ item: ReferenceKey?, instance key: PapyrusInstanceKey) -> Bool {
        let prefix = Self.inventoryFilterPrefix(key)
        let filters = scriptedState(of: key.reference).forms
            .filter { $0.key.hasPrefix(prefix) }.values
        guard !filters.isEmpty else { return true }
        guard let item else { return false }
        return filters.contains { filter in
            filter == item || formListEntries(of: filter)?.contains(item) == true
        }
    }
}
