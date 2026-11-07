// App side of `FollowerCommandCoordinator`: the favour state, the use key and the pause
// key in command mode, and the follower's walk and act. The rules live in the
// coordinator (docs/engine/follower-commands.md).

import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `FollowerCommandWorldAdapter` reads from the session. `GameSessionScope` conforms.
@MainActor
protocol FollowerCommandWorldHost: AnyObject {
    var worldState: WorldStateStore { get }
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var aiWorld: AIWorldAdapter { get }
    var crime: CrimeCoordinator { get }
    var dialogue: DialogueCoordinator { get }
    var followerCommands: FollowerCommandCoordinator { get }
    var furniture: FurnitureCoordinator { get }
    var gameSession: GameSession? { get }
    var inventory: InventoryCoordinator { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
}

final class FollowerCommandWorldAdapter {
    unowned let game: any FollowerCommandWorldHost
    private var pressedTarget: InteractionTarget?

    init(game: any FollowerCommandWorldHost) {
        self.game = game
    }

    func wire(gameSession: GameSession) {
        let commands = game.followerCommands
        gameSession.worldTick.register(.followerCommands) { [weak commands] delta in
            commands?.tick(delta)
        }
    }

    /// `SetDoingFavor` changed the flag: the follower says Show or Exit, and command
    /// mode starts or ends with it.
    func favorStateChanged(_ actor: ReferenceKey, isDoingFavor: Bool) {
        sayFavorLine(isDoingFavor ? "SHOW" : "FEXT", follower: actor)
        if isDoingFavor {
            game.followerCommands.favorStarted(actor)
        } else {
            game.followerCommands.favorEnded(actor)
        }
    }

    /// Starts command mode as the follower's "do something" topic does.
    func enterCommandMode(_ follower: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: follower) {
            $0.setFlag(ScriptedStateName.doingFavor, true)
        }
        favorStateChanged(follower, isDoingFavor: true)
    }

    /// Command mode picks a target farther away than the use key reaches.
    var pickReach: Float {
        let commands = game.followerCommands
        return commands.isChoosing ? commands.settings.pickDistance
            : InteractionRay.defaultMaximumDistance
    }

    /// The use key in command mode commands the target under the crosshair, or the
    /// ground there. True when the press was taken, so nothing in the world activates.
    func takeActivation() -> Bool {
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
    func advanceUseKey(by delta: Float, isDown: Bool) {
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
    static let terrainStep: Float = 32

    /// What the rules know about `key`, or nil when it is nothing a follower can use.
    func commandTarget(_ key: ReferenceKey) -> FollowerCommandTarget? {
        guard let entry = game.streamer?.referenceEntry(key: key) else { return nil }
        var target: FollowerCommandTarget
        if entry.placedActor != nil {
            guard let position = game.aiWorld.packageActorPosition(key) else { return nil }
            let dead = game.aiWorld.packageActorActivity(key) == .dead
            target = FollowerCommandTarget(
                key: key, kind: dead ? .corpse : .actor, position: position
            )
            target.isHostile = game.scripts.bridge?.isHostile(key, toward: .player) == true
        } else {
            guard
                let interaction = game.streamer?.residentInteraction(reference: entry.formID)
            else { return nil }
            target = FollowerCommandTarget(
                key: key, kind: Self.kind(of: interaction), position: interaction.position
            )
            let locks = game.inventory.locks
            if let lock = locks.lock(of: interaction), lock.state.isLocked {
                target.lock = locks.difficulty(of: lock.shown)
            }
            target.isOwned = game.crime.reporter?.verdict(on: key).isTheft == true
        }
        target.noFavorAllowed = game.scripts.bridge?.scriptedState(of: key)
            .flag(Self.noFavorAllowed) == true
        return target
    }

    static let noFavorAllowed = "noFavorAllowed"

    private static func kind(of interaction: PlacedInteraction) -> FollowerCommandTarget.Kind {
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
    func followerCommandPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        game.aiWorld.packageActorPosition(actor)
    }

    var followerCommandPlayerPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    func followerMorality(_ follower: ReferenceKey) -> Float {
        guard
            let index = ActorValueIdentity.index(named: "Morality"),
            let holder = game.actorWorld.actorValueHolder(for: follower)
        else { return 3 }
        return game.actorValues.runtime?.value(at: index, on: holder) ?? 3
    }

    func sayFavorLine(_ subtype: FourCC, follower: ReferenceKey) {
        if let line = game.dialogue.favorLine(subtype, speaker: follower) {
            game.storyWorld.say(line, speaker: follower)
        }
    }

    func endFavor(_ follower: ReferenceKey, announces: Bool) {
        game.scripts.bridge?.updateScriptedState(of: follower) {
            $0.setFlag(ScriptedStateName.doingFavor, nil)
        }
        if announces {
            sayFavorLine("FEXT", follower: follower)
        }
    }

    func moveFollower(_ follower: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        game.aiWorld.movePackageActor(
            follower, to: point, direct: false, gait: nil, walkRunBlend: nil
        ) == .started
    }

    func stopFollower(_ follower: ReferenceKey) {
        game.aiWorld.stopPackageActor(follower)
    }

    func holdFollower(_ follower: ReferenceKey) {
        game.packages.holdCommanded(follower)
    }

    func releaseFollower(_ follower: ReferenceKey) {
        game.packages.releaseCommanded(follower)
    }

    var followerCommandSettings: FollowerCommandSettings {
        game.worldData.map { .resolve(store: $0.gameSettings) } ?? .vanilla
    }

    func performFollowerTask(_ task: FollowerCommandTask, follower: ReferenceKey) -> Bool {
        guard let key = task.target.key else { return false }
        if task.unlocks, !unlock(key, isCrime: task.crime != nil) {
            return false
        }
        switch task.action {
        case .activate where task.target.kind == .furniture:
            if case .success = game.furniture.use(key, by: follower) {
                return true
            }
            return false
        case .activate:
            return game.aiWorld.activate(key, by: follower) == .done
        case .moveTo:
            return true
        case .pickUp:
            return game.inventory.followerPickUp(key, by: follower)
        case .loot:
            return game.inventoryWorld.run(game.inventory.followerTakeAll(from: key, by: follower))
        case .attack:
            if task.crime == .violence {
                game.crime.reportAssault(on: key, wasHostile: false)
            }
            return game.scripts.bridge?.startActorCombat(follower, target: key) == true
        }
    }

    /// The follower opens the lock without lockpicks. Picking an owner's lock is
    /// the player's crime.
    private func unlock(_ key: ReferenceKey, isCrime: Bool) -> Bool {
        guard
            let formID = game.streamer?.referenceEntry(key: key)?.formID,
            let interaction = game.streamer?.residentInteraction(reference: formID)
        else { return false }
        _ = game.inventoryWorld.run(game.inventory.locks.setLocked(interaction, locked: false))
        if isCrime {
            _ = game.crime.reportLockpicking(of: key)
        }
        return true
    }
}
