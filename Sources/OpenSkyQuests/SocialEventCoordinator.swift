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
    /// Sends one event to the story manager, which fills in its location.
    func reportSocialEvent(_ event: StoryEventData)
}

@MainActor
public final class SocialEventCoordinator {
    /// Frames between passes. Each pass reads every loaded actor.
    public static let frameInterval = 30
    public static let historyLimit = 12

    public var settings = SocialSettings.documentedDefaults
    public private(set) var recent: [StoryEventData] = []
    public private(set) var sentCounts: [FourCC: Int] = [:]
    private var state = SocialState()
    private var frames = 0
    weak var world: (any SocialEventWorld)?

    public init() {}

    public func attach(world: any SocialEventWorld) {
        self.world = world
    }

    /// Called once per frame.
    public func tick() {
        frames += 1
        guard frames >= Self.frameInterval else { return }
        frames = 0
        runPass()
    }

    /// One pass now, whatever the frame count.
    public func runPass() {
        guard let world, let frame = world.socialFrame() else { return }
        let events = SocialEventCore.events(frame, settings: settings, state: &state) {
            world.socialCanSee($0, $1)
        }
        for event in events {
            sentCounts[event.event, default: 0] += 1
            world.reportSocialEvent(event)
        }
        recent = Array((recent + events).suffix(Self.historyLimit))
    }

    /// The readout: what each code sent, then the latest events.
    public var lines: [String] {
        let codes: [FourCC] = ["ADIA", "AHEL", "DEAD"]
        let counts = codes.map { "\($0) \(sentCounts[$0] ?? 0)" }
        return ["Social events sent: " + counts.joined(separator: ", ")]
            + recent.reversed().map { event in
                "\(event.event): \(event.actor1?.description ?? "-") to "
                    + (event.actor2?.description ?? "-")
            }
    }

    /// Forgets timers and found bodies, after a load or a new game.
    public func reset() {
        state = SocialState()
        recent = []
    }
}
