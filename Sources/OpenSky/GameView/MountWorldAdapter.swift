// App side of `MountCoordinator`: answers its port from the actors, perks, and crime,
// and applies its commands to the vehicles, the streamer, and the actor graphs. The rules
// live in `MountRules` (docs/engine/riding.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MountWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MountWorldHost: AnyObject {
    var actorGraphWorld: ActorGraphWorldAdapter { get }
    var actorWorld: ActorWorldAdapter { get }
    var aiWorld: AIWorldAdapter { get }
    var crime: CrimeCoordinator { get }
    var gameSession: GameSession? { get }
    var magicWorld: MagicWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var messages: MessageCoordinator { get }
    var perks: PerkCoordinator { get }
    var streamer: CellStreamer? { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldData: WorldDataStores? { get }
}

final class MountWorldAdapter {
    unowned let game: any MountWorldHost
    private(set) lazy var mounts = MountCoordinator(world: self)
    /// How far the sidebar's "Mount nearest" looks. OpenSky's value.
    static let nearestDistance: Float = 1024
    static let dragonKeyword = "ActorTypeDragon"

    init(game: any MountWorldHost) {
        self.game = game
    }

    /// After the locks, whose activation gate this one wraps.
    func wireMounts(gameSession: GameSession) {
        if let store = game.worldData?.gameSettings {
            mounts.settings = MountSettings.resolve(store: store) { [game] in
                game.mapWorld.text($0)
            }
        }
        gameSession.playerMount = self
        guard let streamer = game.streamer else { return }
        let locks = streamer.activationGate.gate
        streamer.activationGate.gate = { [weak self] target in
            if self?.mounts.isActive == true, target.interaction.action == .open {
                return .mounted
            }
            return locks?(target)
        }
        streamer.activationGate.refusals.add { [weak self] event in
            guard let self, event.refusal == .mounted else { return }
            _ = game.messages.postNotification(mounts.settings.doorRefusal)
        }
    }

    /// The use key while a mount is under the player: a seated rider dismounts. True
    /// when the press was taken, so nothing in the world activates.
    func takeActivation() -> Bool {
        guard mounts.isActive else { return false }
        run(mounts.dismount())
        return true
    }

    /// `Actor.Dismount`: the player starts the dismount clips; a package rider steps off.
    func dismount(_ actor: ReferenceKey) -> Bool {
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
    func mountOnActivation(_ key: ReferenceKey) -> Bool {
        guard case .mount = MountRules.decide(mountCandidate(key), isRiding: mounts.isActive)
        else { return false }
        run(mounts.mount(key))
        return true
    }

    /// The player's dragon, for `IsOnFlyingMount`.
    var flyingMounts: Set<ReferenceKey> {
        guard let drive = mounts.drive, drive.kind == .dragon else { return [] }
        return [drive.mount]
    }

    /// `sRide` on an actor the player can mount, else nil.
    func promptLabel(for key: ReferenceKey) -> String? {
        guard case .mount = MountRules.decide(mountCandidate(key), isRiding: mounts.isActive)
        else { return nil }
        return mounts.settings.ride
    }

    func run(_ commands: [MountCommand]) {
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
                _ = locomotion.graphEvents.drain(locomotion.mountEventConsumer)
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
        case let .askToSteal(mount): askToSteal(mount)
        case let .reportTheft(mount):
            let owner = game.crime.ownershipVerdict(on: mount).owner
            game.crime.reporter?.reportHorseTheft(of: mount, owner: owner)
        case let .refused(reason):
            _ = game.messages.postNotification("Cannot mount: \(reason.rawValue).")
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
        MountGraphNames.saddleBones.first {
            game.vehicleWorld.vehicleBone(of: key, named: $0) != nil
        }
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
    func mountCandidate(_ key: ReferenceKey) -> MountCandidate? {
        guard key != .player, let actor = game.actorWorld.combatActor(key: key) else {
            return nil
        }
        var candidate = MountCandidate(key: key)
        candidate.isDead = actor.isDead
        candidate.saddleBone = saddleBone(of: key)
        guard candidate.saddleBone != nil else { return candidate }
        candidate.isDragon = game.magicWorld.actorValueHolder(for: key).map {
            game.magicWorld.actorHasKeyword(Self.dragonKeyword, on: $0)
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

    func nearestMountCandidate() -> ReferenceKey? {
        guard let feet = game.gameSession?.walkController.feetPosition else { return nil }
        return game.actorWorld.combatActors()
            .filter { simd_distance($0.feet, feet) <= Self.nearestDistance }
            .sorted { simd_distance($0.feet, feet) < simd_distance($1.feet, feet) }
            .first { actor in
                guard case .mount = MountRules.decide(mountCandidate(actor.key), isRiding: false)
                else { return false }
                return true
            }?.key
    }

    func takeMount(_ key: ReferenceKey, kind: MountKind, saddleBone: String)
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

    func dismountOffset(of key: ReferenceKey) -> SIMD3<Float> {
        race(of: key)?.details.properties?.mountOffsets?.dismount
            ?? SIMD3(-50, 0, 65)
    }
}

extension MountWorldAdapter: PlayerMountDriving {
    var isMountActive: Bool {
        mounts.isActive
    }

    var maximumLookDown: Float {
        mounts.settings.maximumLookDown
    }

    func advanceMount(
        input: CameraInput, cameraYaw: Float, weaponDrawn: Bool, world: MountStepWorld
    ) -> (motion: MountMotion, yaw: Float)? {
        if let locomotion = game.gameSession?.locomotion {
            run(mounts.handleRiderEvents(
                locomotion.graphEvents.drain(locomotion.mountEventConsumer)
            ))
        }
        run(mounts.advance(
            input: input, cameraYaw: cameraYaw, weaponDrawn: weaponDrawn, world: world
        ))
        guard let drive = mounts.drive else { return nil }
        return (drive.motion, drive.heading)
    }
}

/// World > Player & Locomotion > Mount reads the adapter.
extension MountWorldAdapter: MountControlProviding {
    var mountSnapshot: MountControlSnapshot {
        let readout = mounts.readout
        let keys = [readout.mount, readout.nearest, readout.lastMount].compactMap(\.self)
        let names = Dictionary(keys.map { key in
            (key, game.actorWorld.combatActor(key: key)?.name ?? key.description)
        }) { first, _ in first }
        return MountControlSnapshot(readout: readout, names: names)
    }

    func mountNearest() {
        run(mounts.mountNearest())
    }

    func dismountPlayer() {
        run(mounts.dismount())
    }
}
