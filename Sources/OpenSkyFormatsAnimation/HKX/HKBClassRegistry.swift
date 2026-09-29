// Havok class name -> decoder, so a graph walk needs no switch over class names.
// The class name comes from the virtual-fixup inventory. A census class from
// the vanilla player files that is missing here fails the sweep.

import Foundation

/// Every behavior class OpenSky can decode, keyed by Havok class name.
nonisolated public enum HKBClassRegistry: Sendable {
    /// Decodes the object registered at `target`, or nil when the bytes are
    /// unreadable. Never throws: a malformed object costs that object.
    ///
    /// `@Sendable` so the `decoders` table below can be a `static let`: under
    /// Swift 6 a stored table of plain closures reads as shared mutable state.
    /// Every entry is a static decode function that captures nothing.
    public typealias Decoder = @Sendable (HKXPointerTarget, HKXObjectGraph) -> (any HKBClass)?

    /// Builds a type-erased decoder for one class, so the table below stays a
    /// list of class names rather than a list of closures.
    ///
    /// `Value` is constrained to `Sendable` because the erasing closure below
    /// implicitly captures `Value.Type`, and a metatype is only `Sendable` when
    /// its type is.
    private static func entry<Value: HKBClass & Sendable>(
        _ decode: @escaping @Sendable (HKXPointerTarget, HKXObjectGraph) -> Value?
    ) -> (String, Decoder) {
        (Value.className, { target, graph in decode(target, graph) })
    }

    /// Graph-level classes are decoded by `HKBBehaviorCensus`
    /// and its own types, which predate this protocol; they are listed here as
    /// known-but-not-node classes so the coverage assertion can tell "no
    /// decoder exists" from "decoded elsewhere".
    public static let graphLevelClassNames: Set<String> = [
        "hkRootLevelContainer",
        HKBBehaviorGraph.className,
        HKBBehaviorGraphData.className,
        HKBBehaviorGraphStringData.className,
        HKBVariableValueSet.className
    ]

    public static let decoders: [String: Decoder] = Dictionary(
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

    public static func decoder(for className: String) -> Decoder? {
        decoders[className]
    }

    /// Decodes the object at `target`, looking its class up in the packfile's
    /// inventory. Nil when the location registers no class, when no decoder
    /// exists for it, or when the object's bytes are unreadable.
    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> (any HKBClass)?
    {
        guard let className = graph.className(at: target) else { return nil }
        return decoders[className]?(target, graph)
    }
}
