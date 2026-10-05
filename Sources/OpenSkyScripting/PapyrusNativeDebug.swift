// Debug natives selected from the vanilla PEX census.

import Foundation
import OpenSkyFormatsCore
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    private static var debugLogger: EngineLogger {
        EngineLogger(
            subsystem: Bundle.main.bundleIdentifier ?? "OpenSky",
            category: "PapyrusDebug"
        )
    }

    public static func installDebug(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug",
            functionName: "Trace"
        ) { call, context in
            guard let message = string(call, at: 0) else {
                return failure(call, "Trace needs a string message")
            }
            context.log.append("Trace: \(message)")
            debugLogger.info("\(message, privacy: .public)")
            return .returned(.none)
        })
    }
}
