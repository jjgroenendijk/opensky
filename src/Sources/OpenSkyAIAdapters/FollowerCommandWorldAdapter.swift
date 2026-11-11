// App side of `FollowerCommandCoordinator`: the favour state, the use key and the pause
// key in command mode, and the follower's walk and act. The rules live in the
// coordinator (docs/engine/follower-commands.md).

import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `FollowerCommandWorldAdapter` reads from the session. `GameSessionScope` conforms.
@MainActor
public protocol FollowerCommandWorldHost: AnyObject, SendableMetatype {
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
    var streamer: any CellStreamerPort { get }
    var aiRecords: (any AIRecordsPort)? { get }
}

public final class FollowerCommandWorldAdapter {
    public let game: any FollowerCommandWorldHost
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
        let picked = game.streamer.interactionTarget
            .flatMap { game.streamer.referenceEntry(formID: $0.interaction.reference)?.key }
        let target = picked.flatMap(commandTarget) ?? (picked == nil ? checks.groundTarget() : nil)
        game.followerCommands.command(target)
        return true
    }

    /// A press on a living follower waits: a tap talks, a hold opens command mode.
    private func takeFollowerPress() -> Bool {
        guard
            let target = game.streamer.interactionTarget,
            let key = game.streamer.referenceEntry(formID: target.interaction.reference)?.key,
            game.streamer.referenceEntry(key: key)?.placedActor != nil,
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
                game.streamer.activate(pressedTarget)
            }
            pressedTarget = nil
        case let .hold(follower):
            pressedTarget = nil
            enterCommandMode(follower)
        case nil:
            break
        }
    }

    /// The terrain test's step along the view ray, in units.
    static let terrainStep: Float = 32
}

extension FollowerCommandWorldAdapter: FollowerCommandWorld {
    public func followerCommandPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        game.aiWorld.packageActorPosition(actor)
    }

    public var followerCommandPlayerPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
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
        game.aiWorld.movePackageActor(PackageMove(follower, to: point)) == .started
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
        game.aiRecords.map { .resolve(store: $0.gameSettings) } ?? .vanilla
    }
}

extension FollowerCommandWorldAdapter: FollowerCommandWorldPort {}
