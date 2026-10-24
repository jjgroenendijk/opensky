// The features a `PapyrusWorldStateBridge` reaches, given when it is built.

import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

/// Each seam is optional: a native whose seam is missing fails with a reason.
@MainActor
public struct PapyrusBridgeSeams {
    public var quests: (any QuestAccess)?
    public var inventory: (any PapyrusInventoryBridge)?
    public var alchemy: (any PapyrusAlchemyBridge)?
    public var actorAI: (any PapyrusActorAIBridge)?
    public var furniture: (any PapyrusFurnitureBridge)?
    public var objectAnimation: (any PapyrusObjectAnimationBridge)?
    public var story: (any PapyrusStoryBridge)?
    public var menus: (any PapyrusMenuBridge)?
    public var trapWorld: (any PapyrusTrapWorldBridge)?
    public var presenter: (any PapyrusPresenting)?
    public var itemNotices = ItemNoticeTexts.vanilla
    public var effectPresenter: (any PapyrusEffectPresenting)?
    public var weather: (any PapyrusWeatherControlling)?
    public var music: (any PapyrusMusicControlling)?

    public init() {}
}
