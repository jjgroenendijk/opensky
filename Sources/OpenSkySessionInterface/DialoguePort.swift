public import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `DialogueCoordinator`.
public protocol DialoguePort: AnyObject {
    associatedtype DialogueRuntime: DialogueRuntimePort
    func ambientLines(_ frame: AmbientSpeechFrame, seconds: Float) -> [AmbientLine]
    func claimForceGreet(speaker: ReferenceKey, now: Double) -> Bool
    func combatLine(_ line: NPCSpeechLine, speaker: ReferenceKey, now: Double) -> FormID?
    func commentOnPlayer(
        _ line: NPCSpeechLine,
        witnesses: [AmbientSpeaker],
        now: Double
    ) -> AmbientLine?
    var conversationSpeaker: ReferenceKey? { get }
    func favorLine(_ subtype: FourCC, speaker: ReferenceKey) -> FormID?
    func focus(on speaker: ReferenceKey, playerEye: SIMD3<Float>) -> [DialogueCommand]
    var index: DialogueStore? { get }
    func isSharedReady(_ line: NPCSpeechLine, now: Double) -> Bool
    var lastOutcome: String? { get set }
    func npcLine(_ line: NPCSpeechLine, speaker: ReferenceKey, now: Double) -> FormID?
    func releaseSpeakerFocus() -> [DialogueCommand]
    var runtime: DialogueRuntime? { get }
    var speechTimers: SpeechTimerSettings { get }
    var spokenLine: DialogueSpokenLine? { get }
    var strings: LocalizedStrings? { get }
    func begin(with speaker: ReferenceKey) -> DialogueRuntime?
    func choose(_ id: FormID, speaker: ReferenceKey) -> DialogueResult<TopicInfo?>
    func endConversation()
    func finishResponse(speaker: ReferenceKey?) -> DialogueResponseEnd
    func forcedGoodbye(for speaker: ReferenceKey) -> FormID?
    func recordGreeting(_ info: FormID, speaker: ReferenceKey) -> [DialogueCommand]
    var selection: DialogueSelection { get }

    func walkAway(speaker: ReferenceKey) -> FormID?
}
