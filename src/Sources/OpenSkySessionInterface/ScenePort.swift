public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
public import OpenSkyQuestsInterface

/// What the world adapters use of `SceneCoordinator`.
public protocol ScenePort: AnyObject {
    func actorsInScenes() -> Set<ReferenceKey>
    func conditionResolution(aliases: QuestAliasResolution) -> SceneConditionResolution
    var sceneSnapshot: SceneControlSnapshot { get }
    var catalog: SceneCatalog { get }
    var playing: Set<FormID> { get }
    func questDidStart(_ quest: FormID)
    func scene(holding reference: ReferenceKey) -> FormID?
    func start(_ id: FormID, force: Bool)
    func stop(_ id: FormID)
    func tick() -> [SceneCommand]
}

/// The default arguments a protocol requirement cannot carry.
extension ScenePort {}
