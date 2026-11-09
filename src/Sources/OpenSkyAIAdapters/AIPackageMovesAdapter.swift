import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `AIPackageMovesAdapter` reads from the session.
@MainActor
public protocol AIPackageMovesHost: AnyObject {
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var furniture: any FurniturePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPackageMovesAdapter {
    public let game: any AIPackageMovesHost
}

extension AIPackageMovesAdapter {
    public func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        guard actor != .player else { return game.gameSession?.locomotion.status.feetPosition }
        let streamer = game.streamer
        if let live = streamer.npcTransform(for: actor) {
            return live.position
        }
        return streamer.referenceEntry(key: actor).flatMap(Self.placedPosition)
    }

    public static func placedPosition(_ entry: RuntimeReferenceEntry) -> SIMD3<Float>? {
        entry.placedActor?.placement.position ?? entry.placedReference?.placement.position
    }

    public var packageDrivesPlayer: Bool {
        game.vehicleWorld.isPlayerAIDriven
    }

    /// Places OpenSky can name: a reference, a reference alias, and the actor itself.
    public func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace? {
        let point: SIMD3<Float>? = switch location.kind {
        case .nearReference, .inCell:
            location.formID
                .flatMap { game.streamer.residentReferenceIndex().entry(for: $0) }
                .flatMap(Self.placedPosition)
        case .referenceAlias:
            aliasQuest
                .flatMap {
                    game.scripts.bridge?.questRuntime?.aliasResolution()
                        .reference(alias: location.value, in: $0)
                }
                .flatMap(packageActorPosition)
        case .nearSelf, .nearPackageStart:
            packageActorPosition(actor)
        case .nearEditorLocation:
            game.streamer.referenceEntry(key: actor).flatMap(Self.placedPosition)
        default:
            nil
        }
        return point.map { PackagePlace(point: $0, radius: location.radius) }
    }

    public func packageActorHoldsIdleMarker(_ actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.holdsMarker(actor)
    }

    /// A dragon outdoors flies its package's walks; indoors it walks them.
    public func packageActorFlies(_ actor: ReferenceKey) -> Bool {
        actor != .player && game.streamer.interiorScene == nil
            && game.dragonFlightWorld.actorFliesPackages(actor)
    }

    public func packageSandboxActivityEnded(_ activity: SandboxActivity, actor: ReferenceKey) {
        switch activity {
        case .idleMarker: game.idleWorld.idles.leaveMarker(actor)
        case .wandering: game.idleWorld.idles.allowPreviousMarker(actor)
        default: break
        }
    }

    public func movePackageActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool, gait: LocomotionGait?,
        walkRunBlend: Float?
    ) -> PackageMoveResult {
        if actor == .player {
            return walkPlayer(to: point, direct: direct) ? .started : .failed
        }
        // The exit clip carries the actor out of its seat first.
        if game.furniture.isLeavingSeat(actor) {
            return .busy
        }
        let result = game.streamer.moveActor(
            actor, to: point, direct: direct, gait: gait,
            runSlowdown: game.packages.followRunSlowdown(for: actor), walkRunBlend: walkRunBlend
        )
        game.packages.recordMove(result, for: actor)
        switch result {
        case .started: return .started
        case .moverCapReached: return .busy
        default: return .failed
        }
    }

    /// The player has no NPC mover, so the renderer walks the navmesh path. Without
    /// a path the player walks straight, as a direct move does.
    private func walkPlayer(to point: SIMD3<Float>, direct: Bool) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        let query = NavigationPathQuery(
            start: gameSession.walkController.feetPosition, target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        )
        gameSession.playerWalkIgnoresStatics = direct
        let found = direct ? NavigationPathResult.path(.straight(to: point))
            : game.streamer.findPath(query)
        switch found {
        case let .path(path):
            gameSession.playerWalkPath = path.waypoints + [point]
            game.packages.recordMove(.started, for: .player)
        case let .miss(reason):
            gameSession.playerWalkPath = [point]
            game.packages.recordMove(.noPath(reason), for: .player)
        }
        return true
    }

    /// Each running quest's alias packages, the higher-priority quest first.
    public func packageAliasStacks() -> [ReferenceKey: PackageAliasStack] {
        guard let quests = game.scripts.bridge?.questRuntime else { return [:] }
        var stacks: [ReferenceKey: PackageAliasStack] = [:]
        let running = quests.runningQuests().map(\.quest).sorted { $0.priority > $1.priority }
        for quest in running where quest.aliases.contains(where: { !$0.packages.isEmpty }) {
            guard let table = attempt({ try quests.aliasState(of: quest.formID) }) else { continue }
            for alias in quest.aliases where !alias.packages.isEmpty {
                guard let actor = table.reference(forAlias: alias.id), stacks[actor] == nil else {
                    continue
                }
                stacks[actor] = PackageAliasStack(packages: alias.packages, quest: quest.formID)
            }
        }
        return stacks
    }

    public func packagePatrolPath(
        from start: Package.Target, actor _: ReferenceKey, aliasQuest: FormID?
    ) -> [SIMD3<Float>]? {
        guard
            let key = packageTargetKey(start, aliasQuest: aliasQuest),
            let lookup = game.streamer.placedRecords
        else { return nil }
        let path = lookup.linkedChain(from: key)
        return path.isEmpty ? nil : path
    }

    /// The reference a package's single-reference input names.
    public func packageTargetKey(_ target: Package.Target, aliasQuest: FormID?) -> ReferenceKey? {
        switch target.kind {
        case .specificReference:
            game.scripts.bridge?.formIDResolver.flatMap {
                ReferenceKey.resolve(FormID(target.value), using: $0)
            }
        case .referenceAlias:
            aliasQuest.flatMap {
                game.scripts.bridge?.questRuntime?.aliasResolution()
                    .reference(alias: target.value, in: $0)
            }
        default:
            nil
        }
    }

    public func packageProcedure(_ event: PackageScriptEvent) {
        game.scripts.bridge?.runPackageFragment(
            of: event.package, slot: event.fragmentSlot, actor: event.actor
        )
        game.scripts.bridge?.queuePackageEvent(
            slot: event.fragmentSlot, package: event.package.formID, actor: event.actor
        )
    }
}
