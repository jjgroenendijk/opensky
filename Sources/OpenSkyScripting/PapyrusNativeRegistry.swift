// Case-insensitive native lookup and its bounded headless log.

import Foundation
import OpenSkyConditions
import OSLog

nonisolated public struct PapyrusNativeKey: Equatable, Hashable, Sendable {
    public let scriptName: String
    public let functionName: String

    public init(scriptName: String, functionName: String) {
        self.scriptName = PapyrusRuntime.key(scriptName)
        self.functionName = PapyrusRuntime.key(functionName)
    }
}

nonisolated public struct PapyrusNativeFunction: Sendable {
    public typealias Body = @MainActor @Sendable (
        PapyrusNativeCall,
        PapyrusNativeContext
    ) -> PapyrusNativeResult

    public let scriptName: String
    public let functionName: String
    public let body: Body

    public var key: PapyrusNativeKey {
        PapyrusNativeKey(scriptName: scriptName, functionName: functionName)
    }
}

nonisolated public final class PapyrusNativeLog {
    public let entryLimit: Int
    public let messageLimit: Int

    public private(set) var messages: [String] = []
    public private(set) var total = 0

    public init(entryLimit: Int = 256, messageLimit: Int = 1024) {
        self.entryLimit = max(1, entryLimit)
        self.messageLimit = max(1, messageLimit)
    }

    public func append(_ message: String) {
        total += 1
        messages.append(String(message.prefix(messageLimit)))
        if messages.count > entryLimit {
            messages.removeFirst(messages.count - entryLimit)
        }
    }
}

public final class PapyrusNativeContext {
    public var random: ConditionRandom
    public let log: PapyrusNativeLog
    /// The world a native may read and change, or nil in a headless runtime. A native
    /// that needs it fails rather than guessing.
    public let world: (any PapyrusWorldBridge)?

    public init(
        seed: UInt64 = ConditionRandom.defaultSeed,
        log: PapyrusNativeLog = PapyrusNativeLog(),
        world: (any PapyrusWorldBridge)? = nil
    ) {
        random = ConditionRandom(seed: seed)
        self.log = log
        self.world = world
    }
}

public struct PapyrusNativeRegistry: PapyrusNativeDispatch {
    public static var empty: PapyrusNativeRegistry {
        PapyrusNativeRegistry()
    }

    public static var standard: PapyrusNativeRegistry {
        standard(context: PapyrusNativeContext())
    }

    /// The standard registry over a caller-supplied context, so a world-aware session
    /// installs the same natives with `PapyrusNativeContext.world` set.
    public static func standard(context: PapyrusNativeContext) -> PapyrusNativeRegistry {
        var registry = PapyrusNativeRegistry(context: context)
        PapyrusNativeFunctions.install(into: &registry)
        return registry
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenSky",
        category: "PapyrusNatives"
    )

    public let context: PapyrusNativeContext
    private var functions: [PapyrusNativeKey: PapyrusNativeFunction] = [:]

    public init(context: PapyrusNativeContext = PapyrusNativeContext()) {
        self.context = context
    }

    public mutating func register(_ function: PapyrusNativeFunction) {
        functions[function.key] = function
    }

    public func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
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

    public func contains(scriptName: String, functionName: String) -> Bool {
        functions[
            PapyrusNativeKey(scriptName: scriptName, functionName: functionName)
        ] != nil
    }

    public var count: Int {
        functions.count
    }
}
