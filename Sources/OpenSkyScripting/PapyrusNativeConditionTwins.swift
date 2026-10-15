// Natives that ask the same question as a condition function, answered by that function
// over the runtime condition context, so a script and a condition always agree. The pairs
// come from matching the Creation Kit wiki pages. See docs/engine/papyrus-condition-twins.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    /// Where a condition parameter comes from.
    enum TwinParameter {
        case none
        /// The native's receiver, for a form that is not a reference.
        case receiver
        /// Object argument `n`; `None` passes 0.
        case object(Int)
        case integer(Int)
    }

    /// Who the condition runs on.
    enum TwinSubject {
        case receiver
        case player
    }

    struct ConditionTwin {
        let script: String
        let native: String
        let function: UInt16
        let returnType: PapyrusType
        var subject = TwinSubject.receiver
        var parameter1 = TwinParameter.none
        var parameter2 = TwinParameter.none
    }

    static let conditionTwins: [ConditionTwin] = [
        ConditionTwin(script: "Actor", native: "IsFlying", function: 594, returnType: .boolean),
        ConditionTwin(script: "Actor", native: "IsOnMount", function: 327, returnType: .boolean),
        ConditionTwin(
            script: "Actor", native: "IsBeingRidden", function: 714, returnType: .boolean
        ),
        ConditionTwin(script: "Actor", native: "GetSitState", function: 159, returnType: .integer),
        ConditionTwin(
            script: "Actor", native: "GetSleepState", function: 49, returnType: .integer
        ),
        ConditionTwin(script: "Actor", native: "GetGoldAmount", function: 48, returnType: .integer),
        ConditionTwin(
            script: "Actor", native: "WornHasKeyword", function: 682, returnType: .boolean,
            parameter1: .object(0)
        ),
        ConditionTwin(
            script: "Actor", native: "HasFamilyRelationship", function: 259,
            returnType: .boolean, parameter1: .object(0)
        ),
        ConditionTwin(
            script: "Actor", native: "HasParentRelationship", function: 261,
            returnType: .boolean, parameter1: .object(0)
        ),
        // `HasAssociation(AssociationType akAssociation, Actor akOther = None)`; the
        // condition takes the actor first.
        ConditionTwin(
            script: "Actor", native: "HasAssociation", function: 258, returnType: .boolean,
            parameter1: .object(1), parameter2: .object(0)
        ),
        ConditionTwin(
            script: "ObjectReference", native: "HasEffectKeyword", function: 699,
            returnType: .boolean, parameter1: .object(0)
        ),
        ConditionTwin(
            script: "ObjectReference", native: "IsInDialogueWithPlayer", function: 249,
            returnType: .boolean
        ),
        ConditionTwin(
            script: "ObjectReference", native: "HasRefType", function: 561,
            returnType: .boolean, parameter1: .object(0)
        ),
        ConditionTwin(
            script: "ActorBase", native: "GetDeadCount", function: 84, returnType: .integer,
            subject: .player, parameter1: .receiver
        ),
        ConditionTwin(
            script: "Location", native: "GetRefTypeAliveCount", function: 592,
            returnType: .integer, subject: .player, parameter1: .receiver,
            parameter2: .object(0)
        ),
        ConditionTwin(
            script: "Location", native: "IsLoaded", function: 625, returnType: .boolean,
            subject: .player, parameter1: .receiver
        ),
        ConditionTwin(
            script: "Scene", native: "IsActionComplete", function: 550, returnType: .boolean,
            subject: .player, parameter1: .receiver, parameter2: .integer(0)
        )
    ]

    static func installConditionTwins(into registry: inout PapyrusNativeRegistry) {
        for twin in conditionTwins {
            scriptState(twin.script, twin.native, into: &registry) { call, bridge, key in
                guard
                    let parameter1 = bridge.twinWord(twin.parameter1, call, receiver: key),
                    let parameter2 = bridge.twinWord(twin.parameter2, call, receiver: key)
                else { return failure(call, "\(twin.native) names a form with no FormID") }
                let subject = twin.subject == .player ? ReferenceKey.player : key
                switch bridge.conditionValue(
                    twin.function, on: subject, parameter1: parameter1, parameter2: parameter2
                ) {
                case let .success(value):
                    return .returned(twinValue(value, as: twin.returnType))
                case let .failure(reason):
                    return failure(call, "\(twin.native) has no answer: \(reason)")
                case nil:
                    return needsWorld(call)
                }
            }
        }
    }

    private static func twinValue(_ value: Float, as type: PapyrusType) -> PapyrusValue {
        switch type {
        case .boolean: .boolean(value != 0)
        case .integer: .integer(Int32(value.rounded(.towardZero)))
        default: .float(value)
        }
    }
}

extension PapyrusWorldStateBridge {
    /// The value condition function `index` answers about `subject`, or nil when no
    /// condition context is wired. Parameter words are load-order FormIDs.
    func conditionValue(
        _ index: UInt16, on subject: ReferenceKey, parameter1: UInt32, parameter2: UInt32
    ) -> Result<Float, ConditionFailure>? {
        guard let evaluator = conditionEvaluator?() else { return nil }
        guard let function = evaluator.registry[index] else {
            return .failure(.unknownFunction(index))
        }
        var context = evaluator.context
        context.subject = subject
        if let formIDResolver {
            context.formIDTranslation = FormIDTranslation(
                source: formIDResolver, target: formIDResolver
            )
            context.data = context.data.with(sourcePlugin: FormIDResolver.loadOrderSpaceName)
        }
        var call = ConditionCall(
            condition: Condition(
                probingFunction: index, parameter1: parameter1, parameter2: parameter2
            ),
            context: context
        )
        return function.body(&call)
    }

    /// The load-order FormID of `key`. The player is `PlayerRef`.
    func loadOrderWord(of key: ReferenceKey) -> UInt32? {
        switch key == .player ? .playerReference : key {
        case let .plugin(plugin, objectID):
            formIDResolver?.localFormID(
                of: ResolvedFormID(plugin: plugin, objectID: objectID)
            )?.rawValue
        case let generated:
            SpawnedReferenceIdentity.formID(for: generated)?.rawValue
        }
    }

    fileprivate func twinWord(
        _ parameter: PapyrusNativeFunctions.TwinParameter,
        _ call: PapyrusNativeCall,
        receiver: ReferenceKey
    ) -> UInt32? {
        switch parameter {
        case .none:
            return 0
        case .receiver:
            return loadOrderWord(of: receiver)
        case let .object(index):
            guard let handle = PapyrusNativeFunctions.objectArgument(call, at: index) else {
                return 0
            }
            return referenceKey(for: handle).flatMap(loadOrderWord(of:))
        case let .integer(index):
            return PapyrusNativeFunctions.integer(call, at: index)
                .map { UInt32(bitPattern: $0) } ?? 0
        }
    }
}
