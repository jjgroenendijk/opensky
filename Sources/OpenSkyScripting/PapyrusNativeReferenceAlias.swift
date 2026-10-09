// The `ReferenceAlias` reads and `GetOwningQuest` on an alias or a scene. An alias-typed
// VMAD property binds to the alias script on the filled reference, or to the reference
// itself, so each read returns the reference's own handle
// (<https://ck.uesp.net/wiki/GetReference_-_ReferenceAlias>).

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
                let reference = context.world.flatMap { world in
                    world.referenceKey(for: receiver).flatMap(world.objectHandle(for:))
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
    }
}

extension PapyrusWorldRuntime {
    /// The quest that owns the scene, topic, or package (`PACK` `QNAM`), or whose alias
    /// holds the script, behind `handle`.
    /// A handle of a filled reference names the first quest, by key, that holds it.
    func owningQuest(of handle: PapyrusObjectHandle) -> ReferenceKey? {
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
