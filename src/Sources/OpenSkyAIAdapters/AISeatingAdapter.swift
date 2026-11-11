import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
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
public protocol AISeatingHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var crime: any CrimePort { get }
    var furniture: any FurniturePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var magicWorld: any MagicWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
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
    static let seatLeaveDistance: Float = 256

    /// FURN `NAM1` is on the actor while it uses the furniture, as Papyrus `AddSpell` puts
    /// a spell on it. No vanilla record has one.
    func holdAssociatedSpell(
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
}

extension AISeatingAdapter {
    public func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
        let streamer = game.streamer
        guard
            let formID = streamer.referenceEntry(key: furniture)?.formID
        else { return nil }
        return streamer.residentInteraction(reference: formID)?.seats
    }

    public func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        packageMoves.packageActorPosition(actor)
    }

    /// A crafting station: its furniture names a workbench type. A chair names none.
    public func furnitureIsSpecial(_ furniture: ReferenceKey) -> Bool {
        let streamer = game.streamer
        guard
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

    public func furnitureExitIsLoading(_ actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.isExitLoading(actor)
    }

    public func residentFurniture() -> [ReferenceKey] {
        let streamer = game.streamer
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
