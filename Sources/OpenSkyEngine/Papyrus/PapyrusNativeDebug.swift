// Debug natives selected from the vanilla PEX census.

import Foundation
import OSLog

nonisolated extension PapyrusNativeFunctions {
    private static var debugLogger: Logger {
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "OpenSky",
            category: "PapyrusDebug"
        )
    }

    static func installDebug(into registry: inout PapyrusNativeRegistry) {
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
            functionName: "MessageBox"
        ) { call, context in
            guard let message = string(call, at: 0) else {
                return failure(call, "MessageBox needs a string message")
            }
            context.log.append("MessageBox: \(message)")
            debugLogger.info("MessageBox: \(message, privacy: .public)")
            return .returned(.none)
        })
    }
}
