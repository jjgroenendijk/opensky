// Debug natives selected from the vanilla PEX census. `TraceStack` reads the call stack
// the interpreter appends as a third argument. A user log is a name prefix in the native
// log, not a separate file (<https://ck.uesp.net/wiki/OpenUserLog_-_Debug>).

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
        installUserLogs(into: &registry)
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug",
            functionName: "ToggleMenus"
        ) { call, context in
            guard let toggle = (context.world as? PapyrusWorldStateBridge)?.toggleMenus else {
                return failure(call, "ToggleMenus needs the HUD")
            }
            toggle()
            return .returned(.none)
        })
    }

    private static func installUserLogs(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug",
            functionName: "OpenUserLog"
        ) { call, context in
            guard let name = string(call, at: 0), !name.isEmpty else {
                return failure(call, "OpenUserLog needs a log name")
            }
            return .returned(.boolean(context.openUserLogs.insert(name).inserted))
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug",
            functionName: "CloseUserLog"
        ) { call, context in
            if let name = string(call, at: 0) {
                context.openUserLogs.remove(name)
            }
            return .returned(.none)
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Debug",
            functionName: "TraceUser"
        ) { call, context in
            guard
                let name = string(call, at: 0), context.openUserLogs.contains(name),
                let message = string(call, at: 1)
            else { return .returned(.boolean(false)) }
            context.log.append("\(name): \(message)")
            debugLogger.info("\(name, privacy: .public): \(message, privacy: .public)")
            return .returned(.boolean(true))
        })
    }
}
