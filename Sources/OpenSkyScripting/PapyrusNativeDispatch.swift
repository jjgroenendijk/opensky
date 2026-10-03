// Native-call seam for the headless Papyrus interpreter.

import Foundation
import OpenSkyScriptingInterface

nonisolated public enum PapyrusNativeCallKind: Equatable, Sendable {
    case method
    case parent
    case staticFunction
}

nonisolated public struct PapyrusNativeCall: Equatable, Sendable {
    public let kind: PapyrusNativeCallKind
    public let scriptName: String
    public let functionName: String
    public let receiver: PapyrusObjectHandle?
    public let arguments: [PapyrusValue]
    public let returnType: PapyrusType

    public init(
        kind: PapyrusNativeCallKind,
        scriptName: String,
        functionName: String,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue],
        returnType: PapyrusType = .none
    ) {
        self.kind = kind
        self.scriptName = scriptName
        self.functionName = functionName
        self.receiver = receiver
        self.arguments = arguments
        self.returnType = returnType
    }

    public var qualifiedName: String {
        "\(scriptName).\(functionName)"
    }

    public func returning(_ type: PapyrusType) -> PapyrusNativeCall {
        PapyrusNativeCall(
            kind: kind,
            scriptName: scriptName,
            functionName: functionName,
            receiver: receiver,
            arguments: arguments,
            returnType: type
        )
    }
}

nonisolated public enum PapyrusNativeFailure: Equatable, Sendable {
    case unimplemented(String)
    case invalidArguments(function: String, detail: String)
}

nonisolated public enum PapyrusNativeSuspension: Equatable, Sendable {
    case realSeconds(Double)
    case gameHours(Double)
    /// Waits until the engine answers `token` through
    /// `PapyrusScheduler.answer(_:returning:)`, such as a message box closing.
    case external(UInt64)
}

nonisolated public enum PapyrusNativeDeviation: Equatable, Sendable {
    case deferredAnimation
    /// A registered stub: physics, camera shake, or sound the engine does not run.
    case stubbed
}

nonisolated public enum PapyrusNativeResult: Equatable, Sendable {
    case returned(PapyrusValue)
    case failed(PapyrusNativeFailure)
    case suspended(PapyrusNativeSuspension)
    case deviated(PapyrusValue, PapyrusNativeDeviation)
}

public protocol PapyrusNativeDispatch {
    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult
}

public final class PapyrusRecordingNativeDispatch: PapyrusNativeDispatch {
    public let callLimit: Int
    public var queuedResults: [PapyrusNativeResult]

    public private(set) var calls: [PapyrusNativeCall] = []
    public private(set) var callTotal = 0

    public init(
        callLimit: Int = PapyrusLimits.standard.nativeCallRecords,
        queuedResults: [PapyrusNativeResult] = []
    ) {
        self.callLimit = max(1, callLimit)
        self.queuedResults = queuedResults
    }

    public func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        callTotal += 1
        calls.append(call)
        if calls.count > callLimit {
            calls.removeFirst(calls.count - callLimit)
        }
        return queuedResults.isEmpty
            ? .returned(call.returnType.defaultValue)
            : queuedResults.removeFirst()
    }
}
