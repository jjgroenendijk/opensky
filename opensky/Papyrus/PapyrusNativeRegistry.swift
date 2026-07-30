// Case-insensitive native lookup and its bounded headless log.

import Foundation
import OSLog

nonisolated struct PapyrusNativeKey: Equatable, Hashable, Sendable {
    let scriptName: String
    let functionName: String

    init(scriptName: String, functionName: String) {
        self.scriptName = PapyrusRuntime.key(scriptName)
        self.functionName = PapyrusRuntime.key(functionName)
    }
}

nonisolated struct PapyrusNativeFunction: Sendable {
    typealias Body = @Sendable (
        PapyrusNativeCall,
        PapyrusNativeContext
    ) -> PapyrusNativeResult

    let scriptName: String
    let functionName: String
    let body: Body

    var key: PapyrusNativeKey {
        PapyrusNativeKey(scriptName: scriptName, functionName: functionName)
    }
}

nonisolated final class PapyrusNativeLog {
    let entryLimit: Int
    let messageLimit: Int

    private(set) var messages: [String] = []
    private(set) var total = 0

    init(entryLimit: Int = 256, messageLimit: Int = 1024) {
        self.entryLimit = max(1, entryLimit)
        self.messageLimit = max(1, messageLimit)
    }

    func append(_ message: String) {
        total += 1
        messages.append(String(message.prefix(messageLimit)))
        if messages.count > entryLimit {
            messages.removeFirst(messages.count - entryLimit)
        }
    }
}

nonisolated final class PapyrusNativeContext {
    var random: ConditionRandom
    let log: PapyrusNativeLog

    init(
        seed: UInt64 = ConditionRandom.defaultSeed,
        log: PapyrusNativeLog = PapyrusNativeLog()
    ) {
        random = ConditionRandom(seed: seed)
        self.log = log
    }
}

nonisolated struct PapyrusNativeRegistry: PapyrusNativeDispatch {
    static var empty: PapyrusNativeRegistry {
        PapyrusNativeRegistry()
    }

    static var standard: PapyrusNativeRegistry {
        var registry = PapyrusNativeRegistry()
        PapyrusNativeFunctions.install(into: &registry)
        return registry
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenSky",
        category: "PapyrusNatives"
    )

    let context: PapyrusNativeContext
    private var functions: [PapyrusNativeKey: PapyrusNativeFunction] = [:]

    init(context: PapyrusNativeContext = PapyrusNativeContext()) {
        self.context = context
    }

    mutating func register(_ function: PapyrusNativeFunction) {
        functions[function.key] = function
    }

    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        let key = PapyrusNativeKey(
            scriptName: call.scriptName,
            functionName: call.functionName
        )
        guard let function = functions[key] else {
            let message = "Unimplemented native \(call.qualifiedName)"
            context.log.append(message)
            Self.logger.info("\(message, privacy: .public)")
            return .failed(.unimplemented(call.qualifiedName))
        }
        return function.body(call, context)
    }

    func contains(scriptName: String, functionName: String) -> Bool {
        functions[
            PapyrusNativeKey(scriptName: scriptName, functionName: functionName)
        ] != nil
    }

    var count: Int {
        functions.count
    }

    var keys: [PapyrusNativeKey] {
        functions.keys.sorted {
            $0.scriptName == $1.scriptName
                ? $0.functionName < $1.functionName
                : $0.scriptName < $1.scriptName
        }
    }
}
