// The behavior class registry (todo 14.2): Havok class name -> decoder. This is
// what lets the 14.3 evaluator and `openskycli hkx` walk a behavior graph
// generically, instead of a switch over class names repeated at every call
// site. A packfile object's class name comes from the virtual-fixup inventory
// (`HKXObjectGraph.className(at:)`), so the class name *is* the key; the
// class-name table's signature hash identifies the same class and is recorded
// per decoder in the file headers under docs/formats/hkx-behavior-nodes.md.
//
// The milestone rule is full-graph decode: a class the census reports in the
// vanilla player behavior files and that is missing from this table is a
// failed sweep assertion, not a tolerated tally entry. Classes that appear only
// outside those files are recorded skips.

import Foundation

/// Every behavior class OpenSky can decode, keyed by Havok class name.
nonisolated enum HKBClassRegistry {
    /// Decodes the object registered at `target`, or nil when the bytes are
    /// unreadable. Never throws: a malformed object costs that object.
    typealias Decoder = (HKXPointerTarget, HKXObjectGraph) -> (any HKBClass)?

    /// Builds a type-erased decoder for one class, so the table below stays a
    /// list of class names rather than a list of closures.
    private static func entry<Value: HKBClass>(
        _ decode: @escaping (HKXPointerTarget, HKXObjectGraph) -> Value?
    ) -> (String, Decoder) {
        (Value.className, { target, graph in decode(target, graph) })
    }

    /// Graph-level classes from item 14.1 are decoded by `HKBBehaviorCensus`
    /// and its own types, which predate this protocol; they are listed here as
    /// known-but-not-node classes so the coverage assertion can tell "no
    /// decoder exists" from "decoded elsewhere".
    static let graphLevelClassNames: Set<String> = [
        "hkRootLevelContainer",
        HKBBehaviorGraph.className,
        HKBBehaviorGraphData.className,
        HKBBehaviorGraphStringData.className,
        HKBVariableValueSet.className
    ]

    static let decoders: [String: Decoder] = Dictionary(
        uniqueKeysWithValues: [
            // Bindable leaves and payloads.
            entry(HKBVariableBindingSet.decode),
            entry(HKBBoneWeightArray.decode),
            entry(HKBBoneIndexArray.decode),
            entry(HKBStringEventPayload.decode),
            // State machine.
            entry(HKBStateMachine.decode),
            entry(HKBStateMachineStateInfo.decode),
            entry(HKBStateMachineTransitionInfoArray.decode),
            entry(HKBStateMachineEventPropertyArray.decode),
            // Generators.
            entry(HKBClipGenerator.decode),
            entry(HKBClipTriggerArray.decode),
            entry(HKBBlenderGenerator.decode),
            entry(HKBBlenderGeneratorChild.decode),
            entry(HKBPoseMatchingGenerator.decode),
            entry(HKBManualSelectorGenerator.decode),
            entry(HKBModifierGenerator.decode),
            entry(HKBBehaviorReferenceGenerator.decode),
            entry(HKBBlendingTransitionEffect.decode),
            // Conditions and expressions.
            entry(HKBExpressionCondition.decode),
            entry(HKBStringCondition.decode),
            entry(HKBExpressionDataArray.decode),
            entry(HKBEventRangeDataArray.decode),
            // Stock modifiers.
            entry(HKBModifierList.decode),
            entry(HKBEventDrivenModifier.decode),
            entry(HKBEvaluateExpressionModifier.decode),
            entry(HKBEventsFromRangeModifier.decode),
            entry(HKBTimerModifier.decode),
            entry(HKBDampingModifier.decode),
            entry(HKBTwistModifier.decode),
            entry(HKBRotateCharacterModifier.decode),
            entry(HKBKeyframeBonesModifier.decode),
            entry(HKBGetUpModifier.decode),
            entry(HKBFootIkControlsModifier.decode),
            entry(HKBPoweredRagdollControlsModifier.decode),
            entry(HKBRigidBodyRagdollControlsModifier.decode),
            // Bethesda generators.
            entry(BSSynchronizedClipGenerator.decode),
            entry(BSiStateTaggingGenerator.decode),
            entry(BSBoneSwitchGenerator.decode),
            entry(BSBoneSwitchGeneratorBoneData.decode),
            entry(BSCyclicBlendTransitionGenerator.decode),
            entry(BSOffsetAnimationGenerator.decode),
            // Bethesda modifiers.
            entry(BSIsActiveModifier.decode),
            entry(BSEventEveryNEventsModifier.decode),
            entry(BSEventOnDeactivateModifier.decode),
            entry(BSEventOnFalseToTrueModifier.decode),
            entry(BSInterpValueModifier.decode),
            entry(BSModifyOnceModifier.decode),
            entry(BSSpeedSamplerModifier.decode),
            entry(BSRagdollContactListenerModifier.decode),
            entry(BSDirectAtModifier.decode),
            entry(BSLookAtModifier.decode)
        ]
    )

    /// Every class name this registry decodes, plus the graph-level classes
    /// item 14.1 already covers. The sweep asserts the census class list is a
    /// subset of this.
    static var coveredClassNames: Set<String> {
        Set(decoders.keys).union(graphLevelClassNames)
    }

    static func decoder(for className: String) -> Decoder? {
        decoders[className]
    }

    /// Decodes the object at `target`, looking its class up in the packfile's
    /// inventory. Nil when the location registers no class, when no decoder
    /// exists for it, or when the object's bytes are unreadable.
    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> (any HKBClass)?
    {
        guard let className = graph.className(at: target) else { return nil }
        return decoders[className]?(target, graph)
    }
}
