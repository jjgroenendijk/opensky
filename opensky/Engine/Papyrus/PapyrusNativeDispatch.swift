// Native-call seam for the headless Papyrus interpreter.

import Foundation

nonisolated enum PapyrusNativeCallKind: Equatable, Sendable {
    case method
    case parent
    case staticFunction
}

nonisolated struct PapyrusNativeCall: Equatable, Sendable {
    let kind: PapyrusNativeCallKind
    let scriptName: String
    let functionName: String
    let receiver: PapyrusObjectHandle?
    let arguments: [PapyrusValue]
    let returnType: PapyrusType

    init(
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

    var qualifiedName: String {
        "\(scriptName).\(functionName)"
    }

    func returning(_ type: PapyrusType) -> PapyrusNativeCall {
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

nonisolated enum PapyrusNativeFailure: Equatable, Sendable {
    case unimplemented(String)
    case invalidArguments(function: String, detail: String)
}

nonisolated enum PapyrusNativeSuspension: Equatable, Sendable {
    case realSeconds(Double)
    case gameHours(Double)
}

nonisolated enum PapyrusNativeDeviation: Equatable, Sendable {
    case deferredAnimation
}

nonisolated enum PapyrusNativeResult: Equatable, Sendable {
    case returned(PapyrusValue)
    case failed(PapyrusNativeFailure)
    case suspended(PapyrusNativeSuspension)
    case deviated(PapyrusValue, PapyrusNativeDeviation)
}

nonisolated protocol PapyrusNativeDispatch {
    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult
}

nonisolated final class PapyrusRecordingNativeDispatch: PapyrusNativeDispatch {
    let callLimit: Int
    var queuedResults: [PapyrusNativeResult]

    private(set) var calls: [PapyrusNativeCall] = []
    private(set) var callTotal = 0

    init(
        callLimit: Int = PapyrusLimits.standard.nativeCallRecords,
        queuedResults: [PapyrusNativeResult] = []
    ) {
        self.callLimit = max(1, callLimit)
        self.queuedResults = queuedResults
    }

    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
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
