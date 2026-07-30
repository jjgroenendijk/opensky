// Native-call seam for the headless Papyrus interpreter.
//
// Milestone 11.1.2 deliberately has no world bindings. The default dispatcher
// records every request and returns None. Tests may enqueue a suspension to
// exercise the continuation contract before real latent natives arrive.

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

    var qualifiedName: String {
        "\(scriptName).\(functionName)"
    }
}

nonisolated enum PapyrusNativeResult: Equatable, Sendable {
    case returned(PapyrusValue)
    case suspended
}

nonisolated protocol PapyrusNativeDispatch: AnyObject {
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
        return queuedResults.isEmpty ? .returned(.none) : queuedResults.removeFirst()
    }
}
