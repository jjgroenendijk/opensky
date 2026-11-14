public import OpenSkyActorPresentation
import OpenSkyAIPackages
public import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `IdlePlacementAdapter` reads from the session.
@MainActor
public protocol IdlePlacementHost: AnyObject, SendableMetatype {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var actorWorld: any ActorWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var player: any PlayerPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var actorRecords: (any ActorRecordsPort)? { get }
}

/// Part of `IdleWorldAdapter`, over its own narrow host.
public struct IdlePlacementAdapter {
    public let game: any IdlePlacementHost
}

extension IdlePlacementAdapter {
    public func packageIdleList(_ package: FormID) -> IdlePackageList? {
        IdleSceneReads(game: game).packageIdleList(package)
    }

    public func idleReferencePlacements() -> [IdleReferencePlacement]? {
        IdleSceneReads(game: game).idleReferencePlacements()
    }

    public func idleActors() -> [IdleActorPresence] {
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
            presence.isStill = game.streamer.isActorWalking($0.key) == false
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

    var idleAnimationTime: Float? {
        game.renderer?.animationTime
    }

    public func turnActor(
        _ actor: ReferenceKey, toHeading heading: Float, within tolerance: Float
    ) -> Float? {
        game.streamer.turnActor(actor, toHeading: heading, within: tolerance)
    }

    public func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey) {
        let streamer = game.streamer
        guard
            let placed = streamer.referenceEntry(key: actor)?.placedActor
        else { return }
        streamer.setActorProp(prop, on: placed.formID)
    }

    /// A paired clip poses both actors from one root, so the partner takes the lead's
    /// feet and heading. The player's heading is the camera's yaw turned a quarter.
    public func pairedActorPose(of actor: ReferenceKey) -> PairedActorPose? {
        guard let gameSession = game.gameSession else { return nil }
        guard actor != .player else {
            return PairedActorPose(
                feet: gameSession.walkController.feetPosition,
                heading: NPCYawMath.heading(fromYaw: gameSession.freeFlyCamera.yaw)
            )
        }
        return game.actorWorld.combatActor(key: actor)
            .map { PairedActorPose(feet: $0.feet, heading: $0.facing) }
    }

    public func placePairedActor(_ actor: ReferenceKey, at pose: PairedActorPose) {
        guard let gameSession = game.gameSession else { return }
        if actor == .player {
            gameSession.placePlayerFeet(at: pose.feet)
            gameSession.freeFlyCamera.yaw = NPCYawMath.yaw(fromHeading: pose.heading)
        } else {
            game.streamer.restActor(actor, at: ReferenceTransformOverride(
                position: pose.feet, rotation: SIMD3(0, 0, pose.heading)
            ))
        }
    }

    public func synchronizedMark(of actor: ReferenceKey) -> BehaviorSynchronizedMark? {
        guard actor != .player else {
            return game.gameSession?.playerGraph?.synchronizedMark
        }
        return game.actorGraphWorld.graphInstance(of: actor)?.synchronizedMark
    }

    public func runsOwnGraph(_ actor: ReferenceKey) -> Bool {
        game.actorGraphWorld.graphs.instance(of: actor) != nil
    }

    public func raiseIdleEvent(_ name: String, state: String?, on actor: ReferenceKey) -> Bool {
        guard actor == .player else {
            return game.actorGraphWorld.graphs.raise(name, on: actor)
        }
        game.player.playIdle(named: name, state: state)
        return true
    }
}

/// The idle lists of packages and the places of resident references, for
/// `IdlePlacementAdapter`.
struct IdleSceneReads {
    let game: any IdlePlacementHost

    /// FormIDs inside a package are relative to its plugin when that plugin's move.
    func packageIdleList(_ package: FormID) -> IdlePackageList? {
        guard
            let store = game.actorRecords?.packageStore,
            let idles = store.package(package)?.details.idleAnimations,
            let resolver = store.translation(of: package)?.source ?? game.scripts.bridge?
                .formIDResolver
        else { return nil }
        return IdlePackageList(
            package: package, idles: idles.animations.compactMap(resolver.resolve),
            flags: idles.flags, timer: idles.timer
        )
    }

    func idleReferencePlacements() -> [IdleReferencePlacement]? {
        let streamer = game.streamer
        guard game.renderer != nil else { return nil }
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
}
