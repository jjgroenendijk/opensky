// Debug natives selected from the vanilla PEX census. `TraceStack` reads the call stack
// the interpreter appends as a third argument.

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
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug",
            functionName: "TraceStack"
        ) { call, context in
            let message = string(call, at: 0) ?? "Tracing stack on request"
            let stack = string(call, at: 2) ?? ""
            let text = stack.isEmpty ? message : "\(message)\n\(stack)"
            context.log.append("TraceStack: \(text)")
            switch integer(call, at: 1) ?? 0 {
            case 2: debugLogger.error("\(text, privacy: .public)")
            case 1: debugLogger.warning("\(text, privacy: .public)")
            default: debugLogger.info("\(text, privacy: .public)")
            }
            return .returned(.none)
        })
    }
}
