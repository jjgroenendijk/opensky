// Native-call seam for the headless Papyrus interpreter.

public import DequeModule
import Foundation
public import OpenSkyScriptingInterface

public protocol PapyrusNativeDispatch {
    func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult
}

public final class PapyrusRecordingNativeDispatch: PapyrusNativeDispatch {
    public let callLimit: Int
    public var queuedResults: Deque<PapyrusNativeResult>

    /// Oldest first, at most `callLimit` of them.
    var calls: [PapyrusNativeCall] {
        Array(callRing)
    }

    public private(set) var callTotal = 0
    private var callRing: Deque<PapyrusNativeCall> = []

    public init(
        callLimit: Int = PapyrusLimits.standard.nativeCallRecords,
        queuedResults: [PapyrusNativeResult] = []
    ) {
        self.callLimit = max(1, callLimit)
        self.queuedResults = Deque(queuedResults)
    }

    public func invoke(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        callTotal += 1
        callRing.append(call)
        if callRing.count > callLimit {
            callRing.removeFirst(callRing.count - callLimit)
        }
        return queuedResults.popFirst() ?? .returned(call.returnType.defaultValue)
    }
}
