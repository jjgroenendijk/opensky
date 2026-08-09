// Perception condition functions (issue #202, roadmap item 16.6), split out of
// `ConditionFunctions` the way `ConditionFunctionsActor` is.
//
// These three were waiting on the perception pass rather than on a decode. Each
// is now a pure read of the `detection` seam on `ConditionContext`, with no
// world, no clock and no runtime behind it — which is what lets the whole family
// be driven from a literal in a test.
//
// Indices below are the raw stored numbers; the Creation Kit spells each 4096
// higher. They come from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, whose
// condition-function table lists:
//
//   (Index:   1; Name: 'GetDistance'; ParamType1: ptReference)
//   (Index:  27; Name: 'GetLineOfSight'; ParamType1: ptReference)
//   (Index:  45; Name: 'GetDetected'; ParamType1: ptActor)
//
// Return semantics come from the Creation Kit wiki pages cited at each
// registration.
//
// ## Which way round a pair runs
//
// All three are asked of the run-on reference *about* the parameter reference:
// `[Observer].GetDetected Target`. That direction matters, because detection is
// not symmetric — a guard may have you while you have no idea it is there — and
// getting it backwards would make every stealth condition in a vanilla package
// answer about the wrong actor. `GetDistance` is symmetric and is still
// resolved the same way, so one helper serves all three.
//
// Three misses stay distinct on purpose. A parameter that names no reference
// this session holds is `.unresolvedParameter`, keyed by function index,
// because the *parameter* is what could not be read. A run-on naming nothing is
// `.unresolvedReference`, which `ConditionCall` already produces. And a pair or
// a position the perception pass carries nothing for is
// `.unavailableDetection`: an untracked pair is not an undetected one, and only
// one of those is a real answer.

import Foundation

nonisolated extension ConditionFunctions {
    static func installDetection(_ registry: inout ConditionFunctionRegistry) {
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
    static func detectionPair(
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

    /// The reference parameter 1 names.
    ///
    /// Honours the `useAliases` flag exactly as `ConditionCall.parameter1`
    /// honours a CIS1 name override: with the flag set the word is a quest-alias
    /// index and the reference is whatever fills it, and without it the word is
    /// a FormID the runtime index resolves.
    static func parameterReference(_ call: ConditionCall) -> ReferenceKey? {
        guard let parameter = call.parameter1 else { return nil }
        if call.condition.flags.contains(.useAliases) {
            return call.aliasReference(parameter)
        }
        return call.context.references.entry(for: parameter.asFormID)?.key
    }
}
