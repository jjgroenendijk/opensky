// Perception condition functions, each a pure read of the `detection` seam.
// Raw stored indices from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: 1
// `GetDistance`, 27 `GetLineOfSight`, 45 `GetDetected`. Each asks the run-on
// reference about the parameter, because detection is not symmetric. Misses stay
// distinct: `.unresolvedParameter`, `.unresolvedReference`, and
// `.unavailableDetection` (an untracked pair is not an undetected one).

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installDetection(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the distance between the calling reference and the specified
        // reference." (<https://ck.uesp.net/wiki/GetDistance>) World units, the
        // same units every other distance in this engine is in.
        registry.register(ConditionFunction(
            index: 1,
            name: "GetDistance",
            parameter1: .formID
        ) { call in
            Self.detectionPair(call, index: 1) { context, subject, other in
                context.detection.distance(from: subject, to: other)
            }
        })

        // "Returns 1 if the calling reference has line of sight to the target
        // reference." (<https://ck.uesp.net/wiki/GetLineOfSight>) OpenSky traces
        // that line against static collision only; see
        // `PerceptionWorld.perceptionHasLineOfSight(from:to:)` for why actors do
        // not block it.
        registry.register(ConditionFunction(
            index: 27,
            name: "GetLineOfSight",
            parameter1: .formID
        ) { call in
            Self.detectionPair(call, index: 27) { context, subject, other in
                context.detection.pair(observer: subject, target: other)
                    .map { Self.isTrue($0.hasLineOfSight) }
            }
        })

        // "Returns whether the calling actor has detected the target actor."
        // (<https://ck.uesp.net/wiki/GetDetected>) The full-level state only:
        // a suspicious observer has not detected anything yet, it has somewhere
        // to go and look.
        registry.register(ConditionFunction(
            index: 45,
            name: "GetDetected",
            parameter1: .formID
        ) { call in
            Self.detectionPair(call, index: 45) { context, subject, other in
                context.detection.pair(observer: subject, target: other)
                    .map { Self.isTrue($0.isDetected) }
            }
        })
    }

    /// One pair read: resolve the run-on's reference, resolve parameter 1 onto a
    /// second reference, then let `read` answer about the two of them.
    ///
    /// A nil from `read` is `.unavailableDetection` — the two references
    /// resolved and the perception pass simply carries nothing about them.
    public static func detectionPair(
        _ call: ConditionCall,
        index: UInt16,
        read: (ConditionContext, ReferenceKey, ReferenceKey) -> Float?
    ) -> Result<Float, ConditionFailure> {
        guard let other = parameterReference(call) else {
            return .failure(.unresolvedParameter(index))
        }
        return call.referenceKey().flatMap { subject in
            guard let value = read(call.context, subject, other) else {
                return .failure(.unavailableDetection)
            }
            return .success(value)
        }
    }
}
