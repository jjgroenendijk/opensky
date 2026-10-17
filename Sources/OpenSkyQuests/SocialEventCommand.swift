// What the social pass asks the app to do. See docs/engine/coordinators.md.

import OpenSkyConditions

/// One change to the world outside the social pass.
nonisolated public enum SocialEventCommand: Equatable, Sendable {
    /// Sends the event to the story manager, which fills in its location.
    case reportStoryEvent(StoryEventData)
}
