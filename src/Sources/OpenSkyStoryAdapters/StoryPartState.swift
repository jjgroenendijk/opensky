// What the Story adapter parts remember between calls. The owner keeps one and hands it to
// each part that needs it, so no part holds the owner.

import OpenSkyConditions
public import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkySessionInterface

public final class StoryPartState {
    /// Voice file lengths for scene lines. Nil without game data.
    public var voiceTimer: SceneVoiceTimer?
    /// Voice file paths for scene and menu lines. Nil without game data.
    public var voiceLocator: VoiceLineLocator?
    /// Lines waiting out `fSpeechDelay`, and the ambient speech pass's frame count.
    public var delayedLines: [DelayedLine] = []
    public var framesSinceAmbientSpeech = 0
    public var lastAmbientSpeechSeconds: Double?

    public init() {}
}

extension StoryManagerPort {
    /// An event with no `L1` takes the location of its `R1`, or the player's.
    func fireLocated(_ event: StoryEventData, context: () -> ConditionContext) {
        var event = event
        if event.location1 == nil {
            event.location1 = context().data.currentLocation(of: event.actor1 ?? .player)
        }
        fire(event)
    }
}
