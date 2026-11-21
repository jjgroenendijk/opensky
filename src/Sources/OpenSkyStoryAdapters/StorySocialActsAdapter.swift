// Runs what the social pass decided: story events, topic lines, head turns, and the
// hold and walk of an actor. docs/engine/random-conversations.md.

import Foundation
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyQuestsInterface
public import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `StorySocialActsAdapter` drives in the session.
@MainActor
public protocol StorySocialActsHost: AnyObject, SendableMetatype {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var furniture: any FurniturePort { get }
    var headTracking: any HeadTrackingPort { get }
    var packages: any PackagePort { get }
    var runtimeState: any RuntimeStatePort { get }
    var storyManager: any StoryManagerPort { get }
    var streamer: any CellStreamerPort { get }
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
                let walk = game.storyManager.fireLocated(event) { [game] in
                    game.runtimeState.conditionContext()
                }
                game.storyManager.social.storyEventAnswered(
                    event, startedQuest: !(walk?.startedQuests.isEmpty ?? true)
                )
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
            case let .standUp(actor):
                game.furniture.stand(actor)
            case let .face(actor, point):
                face(actor, toward: point)
            case let .sheathe(actor):
                _ = game.actorGraphWorld.graphs.raise(Self.sheatheEvent, on: actor)
            }
        }
    }

    static let sheatheEvent = "Unequip"
    /// How near the heading a watcher's turn to the fight ends, in radians.
    static let faceToleranceDegrees: Float = 5

    private func face(_ actor: ReferenceKey, toward point: SIMD3<Float>) {
        guard let feet = game.streamer.npcTransform(for: actor)?.placement.position else { return }
        let heading = atan2(point.x - feet.x, point.y - feet.y)
        _ = game.streamer.turnActor(
            actor,
            toHeading: heading,
            within: MatrixMath.radians(fromDegrees: Self.faceToleranceDegrees)
        )
    }
}
