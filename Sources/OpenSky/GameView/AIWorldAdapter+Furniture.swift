// Furniture seats: answers the furniture coordinator's port from the streamer, the
// idles, and the scripts, seats the player each frame, and answers the furniture
// natives. Sit and Sleep packages reach the seats through the package port. See
// docs/engine/furniture.md.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AIWorldAdapter {
    /// After the vehicles, so the switch and the bridge are set before a package sits.
    func wireFurniture(gameSession: GameSession) {
        game.scripts.bridge?.furniture = self
        gameSession.playerFurniture = self
        let furniture = game.furniture
        let store = game.playerSettingsStore
        furniture.isEnabled = store.bool(.furniture)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak furniture, weak store] id in
            guard id == .furniture, let store else { return }
            furniture?.isEnabled = store.bool(.furniture)
        }
        gameSession.worldTick.register(.furniture) { [weak self] _ in
            self?.placeSeatedPlayer()
        }
    }

    func packageSeat(
        in furniture: ReferenceKey, actor: ReferenceKey, animation: UInt16
    ) -> PackageSeat? {
        game.furniture.reserve(in: furniture, for: actor, animation: animation)
    }

    func seatPackageActor(_ actor: ReferenceKey, in seat: PackageSeat) {
        game.furniture.sit(actor, in: seat)
    }

    func unseatPackageActor(_ actor: ReferenceKey, from seat: PackageSeat?) {
        if seat != nil, game.furniture.occupancies[actor]?.seat == seat {
            game.furniture.stand(actor)
        } else {
            game.furniture.releaseReservations(of: actor)
        }
    }

    /// Farther than this from the seat, something else moved the seated player away.
    static let seatLeaveDistance: Float = 256

    /// The body's root sits on the seat and the eye on the seat idle's head bone. A
    /// teleport or a cell change that took the player away ends the seat.
    private func placeSeatedPlayer() {
        guard
            let occupancy = game.furniture.occupancies[.player],
            let gameSession = game.gameSession
        else { return }
        let seat = occupancy.seat.seat
        let feet = gameSession.walkController.feetPosition
        guard
            furnitureSeats(of: occupancy.seat.furniture) != nil,
            simd_distance(feet, seat.position) <= Self.seatLeaveDistance
        else {
            game.furniture.vacate(.player)
            game.idleWorld.idles.leaveFurniture(.player)
            gameSession.playerSeat = nil
            game.scripts.runtime?.queueFurnitureEvent(
                sitting: false, actor: .player, furniture: occupancy.seat.furniture
            )
            return
        }
        seatPlayer(on: seat, gameSession: gameSession)
    }

    private func seatPlayer(on seat: FurnitureSeat, gameSession: GameSession) {
        let root = MatrixMath.placement(
            position: seat.root, rotation: SIMD3(0, 0, seat.heading), scale: 1
        )
        let head = game.idleWorld.idles.idleBone(of: .player, named: DialogueCamera.headBoneName)
        gameSession.seatPlayer(at: root, head: head)
    }
}

extension AIWorldAdapter: FurnitureWorld {
    func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
        guard
            let streamer = game.streamer,
            let formID = streamer.referenceEntry(key: furniture)?.formID
        else { return nil }
        return streamer.residentInteraction(reference: formID)?.seats
    }

    func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        packageActorPosition(actor)
    }

    /// `KWDA` of the actor's base, as the Papyrus `HasKeyword` reads it.
    func furnitureActorHasKeyword(_ actor: ReferenceKey, _ keyword: FormID) -> Bool {
        guard
            let bridge = game.scripts.bridge,
            let keywordKey = bridge.referenceKey(forFormID: keyword)
        else { return false }
        return bridge.formHasKeyword(actor, keyword: keywordKey) == true
    }

    /// An NPC rests on the seat and activates it, so its scripts get `OnActivate`. The
    /// player's own activation already did; the frame step keeps the player seated.
    func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
        let seat = occupancy.seat
        if actor == .player, let gameSession = game.gameSession {
            seatPlayer(on: seat.seat, gameSession: gameSession)
        } else if actor != .player {
            game.streamer?.restActor(actor, at: ReferenceTransformOverride(
                position: seat.seat.root, rotation: SIMD3(0, 0, seat.seat.heading)
            ))
            game.scripts.bridge?.activate(seat.furniture, by: actor, togglesOpen: false)
        }
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

    /// An NPC's package walks it on from the seat; the player stands at `point`.
    func placeStanding(
        _ actor: ReferenceKey, from occupancy: FurnitureOccupancy, at point: SIMD3<Float>
    ) {
        game.idleWorld.idles.leaveFurniture(actor)
        if actor == .player, let gameSession = game.gameSession {
            gameSession.playerSeat = nil
            gameSession.placePlayerFeet(at: point)
        }
        game.scripts.runtime?.queueFurnitureEvent(
            sitting: false, actor: actor, furniture: occupancy.seat.furniture
        )
    }

    func residentFurniture() -> [ReferenceKey] {
        guard let streamer = game.streamer else { return [] }
        return streamer.residentInteractions.filter { !$0.seats.isEmpty }.compactMap {
            streamer.referenceEntry(formID: $0.reference)?.key
        }
    }

    /// Only the first-person view turns, as the Creation Kit wiki says of `SetSittingRotation`.
    func turnSeatedPlayerView(toYaw yaw: Float) {
        guard let gameSession = game.gameSession, gameSession.movementMode == .walk else { return }
        gameSession.freeFlyCamera.yaw = yaw
    }
}

extension AIWorldAdapter: PlayerFurnitureDriving {
    func playerAskedToStand() {
        game.furniture.stand(.player)
    }
}

extension AIWorldAdapter: PapyrusFurnitureBridge {
    func isFurnitureInUse(_ furniture: ReferenceKey, marker: Int?, ignoringReserved: Bool) -> Bool {
        game.furniture.isInUse(furniture, marker: marker, ignoringReserved: ignoringReserved)
    }

    func setSittingRotation(degrees: Float) {
        game.furniture.setSittingRotation(degrees: degrees)
    }
}
