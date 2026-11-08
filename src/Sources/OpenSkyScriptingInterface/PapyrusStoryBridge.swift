import Foundation
public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// What the story and scene natives reach. The app answers it.
public protocol PapyrusStoryBridge: AnyObject {
    /// Fires one event. True when it started a quest.
    func sendStoryEvent(_ event: StoryEventData) -> Bool
    /// True when the scene plays afterwards. `force` first stops the scenes that
    /// share an actor with it.
    func startScene(_ scene: FormID, force: Bool) -> Bool
    func stopScene(_ scene: FormID)
    func isScenePlaying(_ scene: FormID) -> Bool
    /// The playing scene `reference` acts in.
    func currentScene(of reference: ReferenceKey) -> FormID?
}
