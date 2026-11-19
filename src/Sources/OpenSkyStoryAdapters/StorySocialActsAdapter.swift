// Runs what the social pass decided: story events, topic lines, head turns, and the
// hold and walk of an actor. docs/engine/random-conversations.md.

import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyPhysics
import OpenSkyQuestsInterface
public import OpenSkySessionInterface
import OpenSkyWorldInterface

/// What `StorySocialActsAdapter` drives in the session.
@MainActor
public protocol StorySocialActsHost: AnyObject, SendableMetatype {
    var aiWorld: any AIWorldPort { get }
    var headTracking: any HeadTrackingPort { get }
    var packages: any PackagePort { get }
    var runtimeState: any RuntimeStatePort { get }
    var storyManager: any StoryManagerPort { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StorySocialActsAdapter {
    public let game: any StorySocialActsHost
    public let ambientTalk: StoryAmbientTalkAdapter

    /// How long a social look holds before the head goes back to its default. The pass
    /// renews it while the reason lasts.
    static let lookSeconds: Float = 10

    public func tick() {
        run(game.storyManager.social.tick())
    }

    func run(_ commands: [SocialEventCommand]) {
        for command in commands {
            switch command {
            case let .reportStoryEvent(event):
                game.storyManager.fireLocated(event) { [game] in
                    game.runtimeState.conditionContext()
                }
            case let .say(subtype, speaker, lookAt):
                ambientTalk.sayTopic(subtype, speaker: speaker, lookAt: lookAt)
            case let .look(actor, target):
                game.headTracking.setLookTarget(
                    target, for: actor, seconds: target.map { _ in Self.lookSeconds }
                )
            case let .hold(actor):
                game.packages.holdCommanded(actor)
            case let .release(actor):
                game.packages.releaseCommanded(actor)
            case let .walk(actor, point):
                game.packages.holdCommanded(actor)
                _ = game.aiWorld.movePackageActor(PackageMove(actor, to: point, gait: .walk))
            case let .stopWalking(actor):
                game.aiWorld.stopPackageActor(actor)
                game.packages.releaseCommanded(actor)
            }
        }
    }
}
