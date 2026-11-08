public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface

/// What the world adapters use of `JournalCoordinator`.
public protocol JournalPort: AnyObject {
    associatedtype QuestRuntime: QuestRuntimePort
    var runtime: QuestRuntime? { get }
    var strings: LocalizedStrings? { get }
    func entries() -> [JournalQuestStatus]
    var selectedEditorID: String { get }
    @discardableResult func toggleTracking(_ id: FormID) -> Bool?
}
