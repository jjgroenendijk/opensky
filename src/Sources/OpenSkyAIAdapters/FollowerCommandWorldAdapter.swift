// App side of `FollowerCommandCoordinator`: the favour state, the use key and the pause
// key in command mode, and the follower's walk and act. The rules live in the
// coordinator (docs/engine/follower-commands.md).

import OpenSkyActors
public import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `FollowerCommandWorldAdapter` reads from the session. `GameSessionScope` conforms.
@MainActor
public protocol FollowerCommandWorldHost: AnyObject {
    var worldState: any WorldStateStorePort { get }
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var dialogue: any DialoguePort { get }
    var followerCommands: any FollowerCommandPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

public final class FollowerCommandWorldAdapter {
    public unowned let game: any FollowerCommandWorldHost
    private var pressedTarget: InteractionTarget?

    public let tasksHost: any FollowerCommandTasksHost

    public var tasks: FollowerCommandTasksAdapter {
        FollowerCommandTasksAdapter(game: tasksHost
        )
    }

    public init(game: some FollowerCommandWorldHost & FollowerCommandTasksHost) {
        tasksHost = game
        self.game = game
    }

    /// `SetDoingFavor` changed the flag: the follower says Show or Exit, and command
    /// mode starts or ends with it.
    public func favorStateChanged(_ actor: ReferenceKey, isDoingFavor: Bool) {
        sayFavorLine(isDoingFavor ? "SHOW" : "FEXT", follower: actor)
        if isDoingFavor {
            game.followerCommands.favorStarted(actor)
        } else {
            game.followerCommands.favorEnded(actor)
        }
    }

    /// Starts command mode as the follower's "do something" topic does.
    public func enterCommandMode(_ follower: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: follower) {
            $0.setFlag(ScriptedStateName.doingFavor, true)
        }
        favorStateChanged(follower, isDoingFavor: true)
    }

    /// Command mode picks a target farther away than the use key reaches.
    public var pickReach: Float {
        let commands = game.followerCommands
        return commands.isChoosing ? commands.settings.pickDistance
            : InteractionRay.defaultMaximumDistance
    }

    /// The use key in command mode commands the target under the crosshair, or the
    /// ground there. True when the press was taken, so nothing in the world activates.
    public func takeActivation() -> Bool {
        guard game.followerCommands.isChoosing else { return takeFollowerPress() }
        let picked = game.streamer?.interactionTarget
            .flatMap { game.streamer?.referenceEntry(formID: $0.interaction.reference)?.key }
        let target = picked.flatMap(commandTarget) ?? (picked == nil ? groundTarget() : nil)
        game.followerCommands.command(target)
        return true
    }

    /// A press on a living follower waits: a tap talks, a hold opens command mode.
    private func takeFollowerPress() -> Bool {
        guard
            let target = game.streamer?.interactionTarget,
            let key = game.streamer?.referenceEntry(formID: target.interaction.reference)?.key,
            game.streamer?.referenceEntry(key: key)?.placedActor != nil,
            game.aiWorld.packageActorActivity(key) != .dead,
            game.scripts.bridge?.scriptedState(of: key)
                .flag(ScriptedStateName.playerTeammate) == true
        else { return false }
        pressedTarget = target
        game.followerCommands.useKeyDown(on: key)
        return true
    }

    /// Each frame while the use key waits on a follower: a release activates the
    /// follower as a normal press would, and a long enough hold opens command mode.
    public func advanceUseKey(by delta: Float, isDown: Bool) {
        switch game.followerCommands.advanceUseKey(by: delta, isDown: isDown) {
        case .tap:
            if let pressedTarget {
                game.streamer?.activate(pressedTarget)
            }
            pressedTarget = nil
        case let .hold(follower):
            pressedTarget = nil
            enterCommandMode(follower)
        case nil:
            break
        }
    }

    /// The first ground the view ray meets within the pick distance: collision or terrain.
    private func groundTarget() -> FollowerCommandTarget? {
        guard
            let camera = game.gameSession?.freeFlyCamera,
            let ray = InteractionRay(
                origin: camera.position, direction: camera.forward, maximumDistance: pickReach
            )
        else { return nil }
        let hit = game.streamer?.nearestCollisionHit(ray: ray)
        let reach = hit?.distance ?? ray.maximumDistance
        let terrain = stride(from: Self.terrainStep, through: reach, by: Self.terrainStep)
            .lazy.map { ray.origin + ray.direction * $0 }
            .first { point in
                game.streamer?.sampleTerrain(at: SIMD2(point.x, point.y))
                    .map { point.z <= $0.height } ?? false
            }
        guard let point = terrain ?? hit?.position else { return nil }
        return FollowerCommandTarget(key: nil, kind: .ground, position: point)
    }

    /// The terrain test's step along the view ray, in units.
    public static let terrainStep: Float = 32

    public static let noFavorAllowed = "noFavorAllowed"

    public static func kind(of interaction: PlacedInteraction) -> FollowerCommandTarget.Kind {
        switch interaction.action {
        case .take: .item
        case .open: .door
        case .search: .container
        case .talk: .actor
        case .activate, .use, .harvest: interaction.seats.isEmpty ? .activator : .furniture
        }
    }
}

extension FollowerCommandWorldAdapter: FollowerCommandWorld {
    public func followerCommandPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        game.aiWorld.packageActorPosition(actor)
    }

    public var followerCommandPlayerPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    public func followerMorality(_ follower: ReferenceKey) -> Float {
        guard
            let index = ActorValueIdentity.index(named: "Morality"),
            let holder = game.actorWorld.actorValueHolder(for: follower)
        else { return FollowerCommandRules.lawfulMorality }
        return game.actorValues.runtime?.value(at: index, on: holder)
            ?? FollowerCommandRules.lawfulMorality
    }

    public func sayFavorLine(_ subtype: FourCC, follower: ReferenceKey) {
        if let line = game.dialogue.favorLine(subtype, speaker: follower) {
            game.storyWorld.say(line, speaker: follower)
        }
    }

    public func endFavor(_ follower: ReferenceKey, announces: Bool) {
        game.scripts.bridge?.updateScriptedState(of: follower) {
            $0.setFlag(ScriptedStateName.doingFavor, nil)
        }
        if announces {
            sayFavorLine("FEXT", follower: follower)
        }
    }

    public func moveFollower(_ follower: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        game.aiWorld.movePackageActor(
            follower, to: point, direct: false, gait: nil, walkRunBlend: nil
        ) == .started
    }

    public func stopFollower(_ follower: ReferenceKey) {
        game.aiWorld.stopPackageActor(follower)
    }

    public func holdFollower(_ follower: ReferenceKey) {
        game.packages.holdCommanded(follower)
    }

    public func releaseFollower(_ follower: ReferenceKey) {
        game.packages.releaseCommanded(follower)
    }

    public var followerCommandSettings: FollowerCommandSettings {
        game.worldData.map { .resolve(store: $0.gameSettings) } ?? .vanilla
    }
}

extension FollowerCommandWorldAdapter: FollowerCommandWorldPort {}
