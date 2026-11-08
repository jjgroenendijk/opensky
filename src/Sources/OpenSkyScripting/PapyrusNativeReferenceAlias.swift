// The alias natives (<https://ck.uesp.net/wiki/ReferenceAlias_Script>,
// <https://ck.uesp.net/wiki/LocationAlias_Script>) and `GetOwningQuest`. The receiver is
// an alias slot handle, which a VMAD alias property binds to, or an alias script's own
// handle, which is `Self` there and stands for the reference it sits on.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static let referenceAliasReads = ["GetRef", "GetReference", "GetActorRef", "GetActorReference"]

    public static func installReferenceAlias(into registry: inout PapyrusNativeRegistry) {
        for name in referenceAliasReads {
            registry.register(PapyrusNativeFunction(
                scriptName: "ReferenceAlias",
                functionName: name
            ) { call, context in
                guard let receiver = call.receiver else { return .returned(.none) }
                guard let world = context.world else { return .returned(.object(receiver)) }
                let reference = world.referenceKey(for: receiver).flatMap(world.objectHandle(for:))
                if (world as? PapyrusWorldStateBridge)?.world?.aliasSlotsByHandle[receiver] != nil {
                    return .returned(reference.map { .object($0) } ?? .none)
                }
                return .returned(.object(reference ?? receiver))
            })
        }
        for script in ["Alias", "Scene", "TopicInfo", "Package"] {
            registry.register(PapyrusNativeFunction(
                scriptName: script,
                functionName: "GetOwningQuest"
            ) { call, context in
                guard
                    let receiver = call.receiver,
                    let bridge = context.world as? PapyrusWorldStateBridge,
                    let quest = bridge.world?.owningQuest(of: receiver),
                    let handle = bridge.objectHandle(for: quest)
                else { return failure(call, "GetOwningQuest needs a quest that owns the caller") }
                return .returned(.object(handle))
            })
        }
        installAliasWrites(into: &registry)
    }

    /// `ForceRefTo(ObjectReference)`, `Clear()`, `Location GetLocation()`,
    /// `ForceLocationTo(Location)`, and `LocationAlias.Clear()`.
    private static func installAliasWrites(into registry: inout PapyrusNativeRegistry) {
        withAliasSlot("ReferenceAlias", "ForceRefTo", into: &registry) { call, bridge, slot in
            guard
                let handle = objectArgument(call, at: 0),
                let reference = bridge.referenceKey(for: handle)
            else { return failure(call, "ForceRefTo needs a reference; Clear empties an alias") }
            try bridge.forceAlias(slot, to: reference.namingPlayer)
            return .returned(.none)
        }
        withAliasSlot("ReferenceAlias", "Clear", into: &registry) { _, bridge, slot in
            try bridge.forceAlias(slot, to: nil)
            return .returned(.none)
        }
        withAliasSlot("LocationAlias", "GetLocation", into: &registry) { _, bridge, slot in
            guard let location = bridge.world?.aliasLocation(in: slot) else {
                return .returned(.none)
            }
            let handle = bridge.objectHandle(for: ReferenceKey(resolved: location))
            return .returned(handle.map { .object($0) } ?? .none)
        }
        withAliasSlot("LocationAlias", "ForceLocationTo", into: &registry) { call, bridge, slot in
            guard
                let handle = objectArgument(call, at: 0),
                case let .plugin(plugin, objectID)? = bridge.referenceKey(for: handle)
            else { return failure(call, "ForceLocationTo needs a location") }
            try bridge.forceLocationAlias(
                slot, to: ResolvedFormID(plugin: plugin, objectID: objectID)
            )
            return .returned(.none)
        }
        withAliasSlot("LocationAlias", "Clear", into: &registry) { _, bridge, slot in
            try bridge.forceLocationAlias(slot, to: nil)
            return .returned(.none)
        }
    }

    /// Registers a native whose receiver names an alias slot. A thrown quest error
    /// becomes a failure with its reason.
    private static func withAliasSlot(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, PapyrusWorldStateBridge, PapyrusAliasSlot
        ) throws -> PapyrusNativeResult
    ) {
        let native: PapyrusNativeFunction.Body = { call, context in
            guard
                let bridge = context.world as? PapyrusWorldStateBridge,
                let receiver = call.receiver,
                let slot = bridge.world?.aliasSlot(for: receiver)
            else { return failure(call, "\(name) needs an alias of a quest") }
            do {
                return try body(call, bridge, slot)
            } catch {
                return failure(call, "\(name) refused: \(String(describing: error))")
            }
        }
        registry.register(PapyrusNativeFunction(
            scriptName: script,
            functionName: name,
            body: native
        ))
    }
}

extension PapyrusWorldRuntime {
    /// The quest that owns the scene, topic, or package (`PACK` `QNAM`), or whose alias
    /// holds the script, behind `handle`.
    /// A handle of a filled reference names the first quest, by key, that holds it.
    func owningQuest(of handle: PapyrusObjectHandle) -> ReferenceKey? {
        if let slot = aliasSlot(for: handle) {
            return slot.quest
        }
        guard let reference = referenceKey(for: handle) else { return nil }
        if let quest = fragmentQuests[reference] {
            return quest
        }
        let owners = questAliasInstanceKeys.keys.sorted()
        if
            let key = keysByHandle[handle],
            let quest = owners.first(where: { questAliasInstanceKeys[$0]?.contains(key) == true })
        {
            return quest
        }
        return owners
            .first { questAliasInstanceKeys[$0]?.contains { $0.reference == reference } == true }
    }
}
