// The `ReferenceAlias` reads. An alias-typed VMAD property binds to the alias script on
// the filled reference, or to the reference itself, so each read returns the reference's
// own handle (<https://ck.uesp.net/wiki/GetReference_-_ReferenceAlias>).

import Foundation
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
    }
}
