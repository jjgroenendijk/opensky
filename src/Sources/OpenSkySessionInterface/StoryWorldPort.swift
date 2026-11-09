public import OpenSkyConditions
public import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface
public import OpenSkyScriptingInterface
public import OpenSkyWorldState

/// What the world adapters use of `StoryWorldAdapter`.
public protocol StoryWorldPort: AnyObject, PapyrusStoryBridge {
    func commentOnPlayer(_ line: NPCSpeechLine)
    func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float?
    /// The quest runtime the Papyrus `Quest` natives read and write, over `store`.
    func questAccess(
        store: WorldStateStore, quests: QuestStore, locations: LocationStore?
    ) -> any QuestAccess
    func reportKill(victim: ReferenceKey, killer: ReferenceKey?)
    func reportStoryEvent(_ event: StoryEventData)
    func rerunSessionStart()
    func say(_ id: FormID, speaker: ReferenceKey)
    func sayOwnLine(_ line: NPCSpeechLine, speaker: ReferenceKey)
    @discardableResult func sayTopic(
        _ subtype: FourCC,
        speaker: ReferenceKey,
        lookAt: ReferenceKey?
    ) -> Float?
    var sceneSeconds: Double { get }
    var scenes: any ScenePort { get }
    func speak(info id: FormID, speaker: ReferenceKey, lookAt: ReferenceKey?, seconds: Float)
    @discardableResult func startOpeningQuest() -> Bool
    func voicePaths(of info: FormID, speaker: ReferenceKey) -> [String]
}
