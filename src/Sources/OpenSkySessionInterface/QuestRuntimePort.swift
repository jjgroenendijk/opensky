public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface

/// What the world adapters use of `QuestRuntime`.
public protocol QuestRuntimePort: QuestAccess {
    func aliasReference(alias aliasID: UInt32, in id: FormID) -> ReferenceKey?
    func questObjectReferences() -> Set<ReferenceKey>
    var quests: QuestStore { get }
    func runtimeQuests() -> [(quest: Quest, state: QuestRuntimeState)]
    @discardableResult func setStage(_ index: UInt16, on id: FormID, items: [Int]?) throws
        -> QuestRuntimeState
    func state(of id: FormID) throws -> QuestRuntimeState
    func state(editorID: String) throws -> QuestRuntimeState
    func trackedQuests() -> [Quest]

    func aliasState(of id: FormID) throws -> QuestAliasState

    func aliasResolution() -> QuestAliasResolution
}

/// The default arguments a protocol requirement cannot carry.
extension QuestRuntimePort {
    @discardableResult public func setStage(
        _ index: UInt16,
        on id: FormID
    ) throws -> QuestRuntimeState {
        try setStage(index, on: id, items: nil)
    }
}
