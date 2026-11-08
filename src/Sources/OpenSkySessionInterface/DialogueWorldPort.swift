public import OpenSkyConditions
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `DialogueWorldAdapter`.
public protocol DialogueWorldPort: AnyObject {
    func conditionContext() -> ConditionContext
    func headPosition(of actor: ReferenceKey) -> SIMD3<Float>?
    func residentVoiceTypes() -> [ReferenceKey: FormID]
    func run(_ commands: [DialogueCommand])
    func speakerLabel(for speaker: ReferenceKey) -> String
}
