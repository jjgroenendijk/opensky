// The shell of the social pass: every few frames it asks the world for the loaded
// actors, lets `SocialEventCore` pick the `ADIA`, `AHEL`, and `DEAD` events, and
// hands them to the story manager. See docs/engine/random-conversations.md.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// What `SocialEventCoordinator` reads from the running session.
@MainActor
public protocol SocialEventWorld: AnyObject {
    /// Nil while no world is loaded.
    func socialFrame() -> SocialFrame?
    /// Whether `observer` has a clear sight line to `body`.
    func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool
}

@MainActor
public final class SocialEventCoordinator {
    /// Frames between passes. Each pass reads every loaded actor.
    public static let frameInterval = 30
    public static let historyLimit = 12

    public let settings: SocialSettings
    public private(set) var recent: [StoryEventData] = []
    public private(set) var sentCounts: [FourCC: Int] = [:]
    private var state = SocialState()
    private var frames = 0
    let world: any SocialEventWorld
    private var pendingCommands: [SocialEventCommand] = []

    public init(world: any SocialEventWorld, settings: SocialSettings = .documentedDefaults) {
        self.world = world
        self.settings = settings
    }

    /// Called once per frame.
    /// - Returns: the events found since the last call, also by `runPass()`.
    public func tick() -> [SocialEventCommand] {
        frames += 1
        if frames >= Self.frameInterval {
            frames = 0
            runPass()
        }
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// One pass now, whatever the frame count. The next `tick()` returns its events.
    public func runPass() {
        guard let frame = world.socialFrame() else { return }
        let world = world
        let events = SocialEventCore.events(frame, settings: settings, state: &state) {
            world.socialCanSee($0, $1)
        }
        for event in events {
            sentCounts[event.event, default: 0] += 1
        }
        recent = Array((recent + events).suffix(Self.historyLimit))
        pendingCommands += events.map(SocialEventCommand.reportStoryEvent)
    }

    /// Forgets timers and found bodies, after a load or a new game.
    public func reset() {
        state = SocialState()
        recent = []
    }
}
