// M14 behavior-graph deviations required to keep latent animation chains live.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installDeferredAnimation(into registry: inout PapyrusNativeRegistry) {
        for functionName in [
            "PlayAnimation",
            "PlayAnimationAndWait",
            "PlayGamebryoAnimation"
        ] {
            registry.register(PapyrusNativeFunction(
                scriptName: "ObjectReference",
                functionName: functionName
            ) { call, context in
                context.log.append(
                    "Deferred animation \(call.qualifiedName) until M14"
                )
                return .deviated(.boolean(true), .deferredAnimation)
            })
        }
    }
}
