// The readout text of the story manager. Values in, values out.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

public enum StoryManagerCore {
    public static func summary(_ walk: StoryManagerWalk) -> String {
        let started = walk.startedQuests.count
        return "\(walk.event.event): \(walk.steps.count) nodes, \(started) quests started"
    }
}
