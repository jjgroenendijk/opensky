// Keeps every story-manager event a coordinator reports, for tests to read.

import OpenSkyConditions
import OpenSkyFormatsCore

@MainActor
public final class StoryEventRecorder: StoryEventReporting {
    public private(set) var events: [StoryEventData] = []

    public init() {}

    public func reportStoryEvent(_ event: StoryEventData) {
        events.append(event)
    }

    public func events(_ code: String) -> [StoryEventData] {
        events.filter { $0.event.description == code }
    }
}
