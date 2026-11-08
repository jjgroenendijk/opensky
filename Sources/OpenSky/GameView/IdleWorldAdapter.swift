// App side of the idle runtime and the head assembly switch. It answers their
// ports from the session systems and runs the idle pass in the frame loop.
// See docs/engine/coordinators.md.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `IdleWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol IdleWorldHost: AnyObject {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var actorWorld: any ActorWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var packages: any PackagePort { get }
    var player: any PlayerPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var idles: any IdlePort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var scripts: any ScriptPort { get }
    var sessionWiring: WorldSessionWiring { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

final class IdleWorldAdapter {
    unowned let game: any IdleWorldHost
    var idles: any IdlePort {
        game.idles
    }

    init(game: any IdleWorldHost) {
        self.game = game
    }

    /// The clip loader is built first.
    func sessionData() -> IdleSessionData? {
        guard
            let store = game.worldData?.idleStore,
            let files = game.audioFileSystem,
            let clips = game.sessionWiring.animationClips
        else { return nil }
        return IdleSessionData(store: store, files: files, clips: clips)
    }

    /// After packages, because the pass reads each actor's current procedure.
    func wireIdles(gameSession: GameSession) {
        let idles = idles
        guard idles.store != nil else { return }
        gameSession.worldTick.register(.idles) { [weak idles] _ in
            idles?.advance()
        }
    }
}

extension IdleWorldAdapter: IdleWorld {
    func idleAnimationEvent(_ name: String, on actor: ReferenceKey) {
        game.vehicleWorld.handleIdleAnimationEvent(name, from: actor)
    }

    func idleReferencePlacements() -> [IdleReferencePlacement]? {
        guard game.renderer != nil, let streamer = game.streamer else { return nil }
        let scenes = streamer.interiorScene.map { [$0] }
            ?? streamer.composition.cells.values
            .sorted { $0.summary.cellName < $1.summary.cellName }
        return scenes.flatMap { scene in
            scene.references.sortedEntries().compactMap { entry in
                entry.placedReference.map {
                    IdleReferencePlacement(
                        reference: entry.key,
                        base: $0.base,
                        plugin: scene.ownerPluginName ?? "Skyrim.esm",
                        position: $0.placement.position,
                        heading: $0.placement.rotation.z
                    )
                }
            }
        }
    }

    func idleActors() -> [IdleActorPresence] {
        let readouts = game.packages.readouts()
        let packages = Dictionary(
            readouts.compactMap { readout in readout.procedure.map { (readout.actor, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let current = Dictionary(
            readouts.compactMap { readout in readout.currentPackage.map { (readout.actor, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let actors = game.actorWorld.combatActors().map {
            var presence = IdleActorPresence(
                key: $0.key, feet: $0.feet, procedure: packages[$0.key], isDead: $0.isDead
            )
            presence.area = game.packages.sandboxArea(of: $0.key)
            presence.packageIdles = current[$0.key].flatMap(packageIdleList)
            presence.isStill = game.streamer?.isActorWalking($0.key) == false
            return presence
        }
        // The player has no package, so it takes no marker; a script idle still plays.
        let player = game.gameSession.map {
            IdleActorPresence(
                key: .player, feet: $0.walkController.feetPosition, procedure: nil, isDead: false
            )
        }
        return actors + (player.map { [$0] } ?? [])
    }

    /// FormIDs inside a package are relative to its plugin when that plugin's move.
    private func packageIdleList(_ package: FormID) -> IdlePackageList? {
        guard
            let store = game.worldData?.packageStore,
            let idles = store.package(package)?.details.idleAnimations,
            let resolver = store.translation(of: package)?.source ?? game.scripts.bridge?
                .formIDResolver
        else { return nil }
        return IdlePackageList(
            package: package, idles: idles.animations.compactMap(resolver.resolve),
            flags: idles.flags, timer: idles.timer
        )
    }

    func idleConditionContext() -> ConditionContext {
        guard let clock = game.gameSession?.gameClock else { return ConditionContext() }
        var context = game.aiWorld.packageConditionContext(clock: clock)
        // Idle trees test keywords, such as the chopping block's `isExecutioner`.
        context.data = game.runtimeStateWorld.conditionData()
        return context
    }

    var idleStateSequence: UInt64 {
        game.worldState.nextJournalSequence
    }

    var idleAnimationTime: Float? {
        game.renderer?.animationTime
    }

    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        game.aiWorld.moveActor(actor, to: point)
    }

    func turnActor(
        _ actor: ReferenceKey, toHeading heading: Float, within tolerance: Float
    ) -> Float? {
        game.streamer?.turnActor(actor, toHeading: heading, within: tolerance)
    }

    func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey) {
        guard
            let streamer = game.streamer,
            let placed = streamer.referenceEntry(key: actor)?.placedActor
        else { return }
        streamer.setActorProp(prop, on: placed.formID)
    }

    /// A paired clip poses both actors from one root, so the partner takes the lead's
    /// feet and heading. The player's heading is the camera's yaw turned a quarter.
    func pairedActorPose(of actor: ReferenceKey) -> PairedActorPose? {
        guard let gameSession = game.gameSession else { return nil }
        guard actor != .player else {
            return PairedActorPose(
                feet: gameSession.walkController.feetPosition,
                heading: Float.pi / 2 - gameSession.freeFlyCamera.yaw
            )
        }
        return game.actorWorld.combatActor(key: actor)
            .map { PairedActorPose(feet: $0.feet, heading: $0.facing) }
    }

    func placePairedActor(_ actor: ReferenceKey, at pose: PairedActorPose) {
        guard let gameSession = game.gameSession else { return }
        if actor == .player {
            gameSession.placePlayerFeet(at: pose.feet)
            gameSession.freeFlyCamera.yaw = Float.pi / 2 - pose.heading
        } else {
            game.streamer?.restActor(actor, at: ReferenceTransformOverride(
                position: pose.feet, rotation: SIMD3(0, 0, pose.heading)
            ))
        }
    }

    func synchronizedMark(of actor: ReferenceKey) -> BehaviorSynchronizedMark? {
        guard actor != .player else {
            return game.gameSession?.locomotion.graph?.synchronizedMark
        }
        return game.actorGraphWorld.graphs.instance(of: actor)?.synchronizedMark
    }

    func raiseIdleEvent(_ name: String, state: String?, on actor: ReferenceKey) -> Bool {
        guard actor == .player else {
            return game.actorGraphWorld.graphs.raise(name, on: actor)
        }
        game.player.playIdle(named: name, state: state)
        return true
    }
}
