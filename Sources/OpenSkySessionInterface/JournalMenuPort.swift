public import OpenSkyMenusInterface

/// What the world adapters use of `JournalMenuController`.
public protocol JournalMenuPort: AnyObject {
    associatedtype QuestRuntime: QuestRuntimePort
    func open()
    var questRuntime: QuestRuntime? { get }
    var snapshot: JournalControlSnapshot { get }
    var currentAliasNaming: QuestAliasNaming? { get }

    func route(_ event: MenuInputEvent)
}
