import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AISeatingAdapter` reads from the session.
@MainActor
public protocol AISeatingHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var crime: any CrimePort { get }
    var furniture: any FurniturePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var magicWorld: any MagicWorldPort { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AISeatingAdapter {
    public let game: any AISeatingHost
    public let packageMoves: AIPackageMovesAdapter
}

extension AISeatingAdapter {
    public func packageSeat(
        in furniture: ReferenceKey, actor: ReferenceKey, animation: UInt16
    ) -> PackageSeat? {
        game.furniture.reserve(in: furniture, for: actor, animation: animation)
    }

    public func packageSandboxSeat(
        for actor: ReferenceKey, in request: SandboxSeatRequest
    ) -> PackageSeat? {
        game.furniture.sandboxSeat(for: actor, in: request)
    }

    /// A package that seats the AI-driven player activates the furniture for it, as its
    /// own activation would. The opening's chopping block waits for that `OnActivate`.
    public func seatPackageActor(_ actor: ReferenceKey, in seat: PackageSeat) {
        // A dragon's sit is its perch, which the dragon flight lands on.
        guard !packageMoves.packageActorFlies(actor) else { return }
        let isNewSeat = game.furniture.occupancies[actor]?.seat != seat
        guard game.furniture.sit(actor, in: seat) != nil, isNewSeat, actor == .player else {
            return
        }
        game.scripts.bridge?.activate(seat.furniture, by: actor, togglesOpen: false)
    }

    public func unseatPackageActor(_ actor: ReferenceKey, from seat: PackageSeat?) {
        if seat != nil, game.furniture.occupancies[actor]?.seat == seat {
            game.furniture.stand(actor)
        } else {
            game.furniture.releaseReservations(of: actor)
        }
    }

    /// Farther than this from the seat, something else moved the seated player away.
    public static let seatLeaveDistance: Float = 256

    /// A teleport or a cell change that took the seated or rising player away ends the seat.
    func releaseMovedPlayer() {
        let seated = game.furniture.occupancies[.player]
        guard
            let occupancy = seated ?? game.furniture.exits[.player],
            let gameSession = game.gameSession
        else { return }
        let feet = gameSession.walkController.feetPosition
        guard
            furnitureSeats(of: occupancy.seat.furniture) == nil
            || simd_distance(feet, occupancy.seat.seat.position) > Self.seatLeaveDistance
        else { return }
        game.furniture.vacate(.player)
        holdAssociatedSpell(of: occupancy.seat.seat, on: .player, while: false)
        game.idleWorld.idles.leaveFurniture(.player, playsExit: false)
        gameSession.playerSeat = nil
        if seated != nil {
            game.scripts.runtime?.queueFurnitureEvent(
                sitting: false, actor: .player, furniture: occupancy.seat.furniture
            )
        }
    }

    /// FURN `NAM1` is on the actor while it uses the furniture, as Papyrus `AddSpell` puts
    /// a spell on it. No vanilla record has one.
    private func holdAssociatedSpell(
        of seat: FurnitureSeat,
        on actor: ReferenceKey,
        while held: Bool
    ) {
        guard
            let spell = seat.rules.associatedSpell,
            let bridge = game.scripts.bridge,
            let key = bridge.referenceKey(forFormID: spell)
        else { return }
        if held {
            bridge.addSpell(key, to: actor)
        } else {
            bridge.removeSpell(key, from: actor)
        }
    }

    /// The body's root goes on the pose and the eye on the idle's head bone.
    private func seatPlayer(at pose: FurniturePose, gameSession: any GameSessionPort) {
        let root = MatrixMath.placement(
            position: pose.root, rotation: SIMD3(0, 0, pose.heading), scale: 1
        )
        let head = game.idleWorld.idles.idleBone(of: .player, named: DialogueCamera.headBoneName)
        gameSession.seatPlayer(at: root, head: head)
    }
}

extension AISeatingAdapter {
    public func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
        guard
            let streamer = game.streamer,
            let formID = streamer.referenceEntry(key: furniture)?.formID
        else { return nil }
        return streamer.residentInteraction(reference: formID)?.seats
    }

    public func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        packageMoves.packageActorPosition(actor)
    }

    /// A crafting station: its furniture names a workbench type. A chair names none.
    public func furnitureIsSpecial(_ furniture: ReferenceKey) -> Bool {
        guard
            let streamer = game.streamer,
            let formID = streamer.referenceEntry(key: furniture)?.formID
        else { return false }
        let station = streamer.residentInteraction(reference: formID)?.station
        return (station?.workbench.benchType ?? WorkbenchType.none) != WorkbenchType.none
    }

    /// The reference's own owner, then its cell's, as the crime rules read them.
    public func furnitureOwnerAllows(_ actor: ReferenceKey, _ furniture: ReferenceKey) -> Bool {
        let owner = game.crime.crimeOwner(of: furniture)
        if case .forbidden = game.crime.crimeActor(actor).verdict(on: owner) {
            return false
        }
        return true
    }

    public func furnitureActorTraits(_ actor: ReferenceKey) -> FurnitureActorTraits {
        guard
            let holder = game.actorWorld.actorValueHolder(for: actor),
            let values = game.actorValues.runtime
        else { return FurnitureActorTraits() }
        return FurnitureActorTraits(
            isChild: values.baseline(of: holder).isChild,
            isDragon: game.magicWorld.actorHasKeyword(ActorTypeKeyword.dragon, on: holder)
        )
    }

    /// `KWDA` of the actor's base, as the Papyrus `HasKeyword` reads it.
    public func furnitureActorHasKeyword(_ actor: ReferenceKey, _ keyword: FormID) -> Bool {
        guard
            let bridge = game.scripts.bridge,
            let keywordKey = bridge.referenceKey(forFormID: keyword)
        else { return false }
        return bridge.formHasKeyword(actor, keyword: keywordKey) == true
    }

    /// An NPC rests on the seat and activates it, so its scripts get `OnActivate`. The
    /// player's own activation already did; the frame step keeps the player seated.
    public func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
        let seat = occupancy.seat
        if actor == .player, let gameSession = game.gameSession {
            seatPlayer(at: seat.seat.seatedPose, gameSession: gameSession)
        } else if actor != .player {
            game.streamer?.restActor(actor, at: ReferenceTransformOverride(
                position: seat.seat.root, rotation: SIMD3(0, 0, seat.seat.heading)
            ))
            game.scripts.bridge?.activate(seat.furniture, by: actor, togglesOpen: false)
        }
        holdAssociatedSpell(of: seat.seat, on: actor, while: true)
        game.idleWorld.idles.enterFurniture(actor, use: FurnitureUse(
            sitState: .readyToSit,
            animationType: UInt32(seat.seat.animationType),
            entry: UInt32(occupancy.entry) << 16,
            furniture: seat.furniture
        ))
        game.scripts.runtime?.queueFurnitureEvent(
            sitting: true, actor: actor, furniture: seat.furniture
        )
    }

    public func placeStanding(_ actor: ReferenceKey, from occupancy: FurnitureOccupancy) {
        holdAssociatedSpell(of: occupancy.seat.seat, on: actor, while: false)
        game.idleWorld.idles.leaveFurniture(actor)
        game.scripts.runtime?.queueFurnitureEvent(
            sitting: false, actor: actor, furniture: occupancy.seat.furniture
        )
    }

    public func furnitureExitIsLoading(_ actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.isExitLoading(actor)
    }

    public func furnitureMotion(of actor: ReferenceKey) -> FurnitureMotionSample? {
        guard let playing = game.idleWorld.idles.rootMotion(of: actor) else { return nil }
        let (motion, elapsed) = playing
        return FurnitureMotionSample(
            offset: motion.offset(at: elapsed), yaw: motion.yaw(at: elapsed),
            endOffset: motion.offset(at: motion.duration), endYaw: motion.yaw(at: motion.duration),
            isFinished: elapsed >= motion.duration
        )
    }

    public func moveFurnitureActor(_ actor: ReferenceKey, to pose: FurniturePose) {
        if actor == .player {
            if let gameSession = game.gameSession {
                seatPlayer(at: pose, gameSession: gameSession)
            }
        } else {
            game.streamer?.restActor(actor, at: ReferenceTransformOverride(
                position: pose.root, rotation: SIMD3(0, 0, pose.heading)
            ))
        }
    }

    /// The player walks on from `pose`, facing its way; an NPC's package walks it on.
    public func finishStanding(_ actor: ReferenceKey, at pose: FurniturePose) {
        guard actor == .player, let gameSession = game.gameSession else {
            moveFurnitureActor(actor, to: pose)
            return
        }
        gameSession.playerSeat = nil
        gameSession.placePlayerFeet(at: pose.root)
        if gameSession.movementMode == .walk {
            gameSession.freeFlyCamera.yaw = NPCYawMath.yaw(fromHeading: pose.heading)
        }
    }

    public func residentFurniture() -> [ReferenceKey] {
        guard let streamer = game.streamer else { return [] }
        return streamer.residentInteractions.filter { !$0.seats.isEmpty }.compactMap {
            streamer.referenceEntry(formID: $0.reference)?.key
        }
    }

    /// Only the first-person view turns, as the Creation Kit wiki says of `SetSittingRotation`.
    public func turnSeatedPlayerView(toYaw yaw: Float) {
        guard let gameSession = game.gameSession, gameSession.movementMode == .walk else { return }
        gameSession.freeFlyCamera.yaw = yaw
    }
}

extension AISeatingAdapter {
    public func playerAskedToStand() {
        game.furniture.stand(.player)
    }
}

extension AISeatingAdapter {
    public func isFurnitureInUse(
        _ furniture: ReferenceKey,
        marker: Int?,
        ignoringReserved: Bool
    ) -> Bool {
        game.furniture.isInUse(furniture, marker: marker, ignoringReserved: ignoringReserved)
    }

    public func setSittingRotation(degrees: Float) {
        game.furniture.setSittingRotation(degrees: degrees)
        game.vehicleWorld.setSittingRotation(degrees: degrees)
    }
}
