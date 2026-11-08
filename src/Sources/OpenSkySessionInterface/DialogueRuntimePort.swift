public import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `DialogueRuntime`.
public protocol DialogueRuntimePort: DialogueAccess {
    @discardableResult func choose(_ id: FormID, speaker: ReferenceKey) throws -> DialogueChoice
    var dialogue: DialogueStore { get }
    func topics(for speaker: ReferenceKey) -> DialogueSelection
    func topics(subtype: FourCC, speaker: ReferenceKey) -> DialogueSelection
    func topics(linked ids: [FormID], speaker: ReferenceKey) -> DialogueSelection
}
