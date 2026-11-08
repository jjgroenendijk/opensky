// App side of `MountCoordinator`: answers its port from the actors, perks, and crime,
// and applies its commands to the vehicles, the streamer, and the actor graphs. The rules
// live in `MountRules` (docs/engine/riding.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
public import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
public import OpenSkyRendering
import OpenSkyScripting
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MountWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MountWorldHost: AnyObject {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var actorWorld: any ActorWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var mounts: any MountPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magicWorld: any MagicWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var perks: any PerkPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var worldData: WorldDataStores? { get }
}

public final class MountWorldAdapter {
    public unowned let game: any MountWorldHost
    public var mounts: any MountPort {
        game.mounts
    }

    public let dragonRidingHost: any MountDragonRidingHost

    public var dragonRiding: MountDragonRidingAdapter {
        MountDragonRidingAdapter(
            owner: self,
            game: dragonRidingHost
        )
    }

    public init(game: some MountWorldHost & MountDragonRidingHost) {
        dragonRidingHost = game
        self.game = game
    }

    /// The use key while a mount is under the player: a seated rider dismounts. True
    /// when the press was taken, so nothing in the world activates.
    public func takeActivation() -> Bool {
        guard mounts.isActive else { return false }
        run(mounts.dismount())
        return true
    }

    /// `Actor.Dismount`: the player starts the dismount clips; a package rider steps off.
    public func dismount(_ actor: ReferenceKey) -> Bool {
        guard actor != .player else {
            let commands = mounts.dismount()
            run(commands)
            return !commands.isEmpty
        }
        guard game.vehicleWorld.vehicles.core.mounts[actor] != nil else { return false }
        game.aiWorld.dismountPackageActor(actor)
        return true
    }

    /// A use-key press on an actor the player can mount mounts it. True when it did.
    public func mountOnActivation(_ key: ReferenceKey) -> Bool {
        guard case .mount = MountRules.decide(mountCandidate(key), isRiding: mounts.isActive)
        else { return false }
        run(mounts.mount(key))
        return true
    }

    /// The player's dragon while it flies, for `IsOnFlyingMount`.
    public var flyingMounts: Set<ReferenceKey> {
        guard let drive = mounts.drive, drive.flight?.phase.isFlying == true else { return [] }
        return [drive.mount]
    }

    /// `sRide` on an actor the player can mount, else nil.
    public func promptLabel(for key: ReferenceKey) -> String? {
        guard case .mount = MountRules.decide(mountCandidate(key), isRiding: mounts.isActive)
        else { return nil }
        return mounts.settings.ride
    }

    public func run(_ commands: [MountCommand]) {
        for command in commands {
            apply(command)
        }
    }

    private func apply(_ command: MountCommand) {
        let vehicles = game.vehicleWorld.vehicles
        switch command {
        case let .boardPlayer(mount):
            // A paired clip's end event from before this phase must not end it.
            if let locomotion = game.gameSession?.locomotion {
                locomotion.drainMountEvents()
            }
            vehicles.board(.player, on: mount)
        case let .seatPlayer(mount, bone): vehicles.seat(.player, on: mount, bone: bone)
        case .detachPlayer:
            game.vehicleWorld.detach(.player)
            game.gameSession?.playerSeat = nil
        case let .placePlayer(feet, yaw):
            game.gameSession?.placePlayerFeet(at: feet)
            game.gameSession?.freeFlyCamera.yaw = yaw
        case let .raiseOnPlayer(event): game.gameSession?.locomotion.raise(event)
        case let .steerMount(mount, feet, yaw): game.streamer?.steerRiddenActor(
                mount,
                to: feet,
                yaw: yaw
            )
        case let .reportMountEvents(mount, events):
            game.actorGraphWorld.graphs.report(events, from: mount)
        case let .releaseMount(mount):
            game.streamer?.releaseRiddenActor(mount)
            game.actorGraphWorld.graphs.giveBack(mount)
        case .askToSteal, .reportTheft, .refused, .notify, .dragonBreath:
            applyOutcome(command)
        }
    }

    /// The commands that reach crime, messages, and magic rather than the bodies.
    private func applyOutcome(_ command: MountCommand) {
        switch command {
        case let .askToSteal(mount): askToSteal(mount)
        case let .reportTheft(mount):
            let owner = game.crime.ownershipVerdict(on: mount).owner
            game.crime.reporter?.reportHorseTheft(of: mount, owner: owner)
        case let .refused(reason):
            _ = game.messages.postNotification("Cannot mount: \(reason.rawValue).")
        case let .notify(text): _ = game.messages.postNotification(text)
        case let .dragonBreath(mount, target): dragonRiding.breathe(from: mount, at: target)
        default: break
        }
    }

    private func askToSteal(_ mount: ReferenceKey) {
        let settings = mounts.settings
        let answered: (Int) -> Void = { [weak self] answer in
            guard answer == 0, let self else { return }
            run(mounts.mount(mount, stealConfirmed: true))
        }
        game.messages.presentChoices(
            title: nil, text: settings.stealQuestion, buttons: [settings.yes, settings.no],
            answer: answered
        )
    }

    private func saddleBone(of key: ReferenceKey) -> String? {
        MountGraphNames.saddleBones.first { game.vehicleWorld.vehicleHasBone(key, named: $0) }
    }

    private func race(of key: ReferenceKey) -> Race? {
        guard
            let base = game.streamer?.residentActorEntry(key: key)?.placedActor?.base,
            let resolver = game.worldData?.actorValueBaselines?.resolver
        else { return nil }
        let identity = ActorIdentityRecords(resolver: resolver)
        return identity.race(ofBase: base).flatMap { identity.races[$0.rawValue] }
    }

    private func allowMountActor(on key: ReferenceKey) -> Float {
        game.perks.modified(
            0,
            at: .allowMountActor,
            on: .player,
            subjects: { _ in PerkEvaluationSubjects(owner: .player, target: key) },
            seams: ConditionContext()
        )
    }
}

extension MountWorldAdapter: MountWorld {
    public func mountCandidate(_ key: ReferenceKey) -> MountCandidate? {
        guard key != .player, let actor = game.actorWorld.combatActor(key: key) else {
            return nil
        }
        var candidate = MountCandidate()
        candidate.isDead = actor.isDead
        candidate.saddleBone = saddleBone(of: key)
        guard candidate.saddleBone != nil else { return candidate }
        candidate.isDragon = game.magicWorld.actorValueHolder(for: key).map {
            game.magicWorld.actorHasKeyword(ActorTypeKeyword.dragon, on: $0)
        } ?? false
        if candidate.isDragon {
            candidate.allowMountActor = allowMountActor(on: key)
        }
        let carried = game.vehicleWorld.vehicles.core.links
        candidate.isRidden = carried.contains { $0.key != .player && $0.value.carrier == key }
        if game.crime.ownershipVerdict(on: key).isTheft {
            candidate.ownership = .other
        }
        return candidate
    }

    public func takeMount(_ key: ReferenceKey, kind: MountKind, saddleBone: String)
        -> PlayerMountDriveStart?
    {
        guard let hold = game.streamer?.takeRiddenActor(key) else { return nil }
        let loan = game.actorGraphWorld.graphs.lend(key)
        return PlayerMountDriveStart(
            mount: key, kind: kind, saddleBone: saddleBone, feet: hold.feetPosition,
            yaw: hold.yaw, graph: loan?.instance, pose: loan?.pose ?? PlayerPoseBuffer(),
            configuration: game.worldData?.mountMovementConfiguration ?? .synthetic
        )
    }

    public func dismountOffset(of key: ReferenceKey) -> SIMD3<Float> {
        race(of: key)?.details.properties?.mountOffsets?.dismount
            ?? RaceProperties.MountOffsets.fallbackDismount
    }
}

extension MountWorldAdapter: PlayerMountDriving {
    public var isMountActive: Bool {
        mounts.isActive
    }

    public var maximumLookDown: Float {
        mounts.settings.maximumLookDown
    }

    public var mountKind: MountKind? {
        mounts.drive?.kind
    }

    public func advanceMount(
        input: CameraInput, cameraYaw: Float, weaponDrawn: Bool, world: MountStepWorld
    ) -> (motion: MountMotion, yaw: Float)? {
        if let locomotion = game.gameSession?.locomotion {
            run(mounts.handleRiderEvents(
                locomotion.drainMountEvents()
            ))
        }
        run(mounts.advance(
            input: input, cameraYaw: cameraYaw, weaponDrawn: weaponDrawn, world: world
        ))
        guard let drive = mounts.drive else { return nil }
        return (drive.motion, drive.heading)
    }
}

extension MountWorldAdapter: MountWorldPort {}
