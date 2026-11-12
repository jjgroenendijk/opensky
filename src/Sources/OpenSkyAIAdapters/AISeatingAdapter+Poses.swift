// Places a seated or standing actor and the player at a furniture pose.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
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
import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AISeatingAdapter {
    public var poses: Poses {
        Poses(owner: self, game: game)
    }

    public struct Poses {
        let owner: AISeatingAdapter
        let game: any AISeatingHost

        /// A teleport or a cell change that took the seated or rising player away ends the seat.
        func releaseMovedPlayer() {
            let seated = game.furniture.occupancies[.player]
            guard
                let occupancy = seated ?? game.furniture.exits[.player],
                let gameSession = game.gameSession
            else { return }
            let feet = gameSession.walkController.feetPosition
            guard
                owner.furnitureSeats(of: occupancy.seat.furniture) == nil
                || simd_distance(feet, occupancy.seat.seat.position) > AISeatingAdapter
                .seatLeaveDistance
            else { return }
            game.furniture.vacate(.player)
            owner.holdAssociatedSpell(of: occupancy.seat.seat, on: .player, while: false)
            game.idleWorld.idles.leaveFurniture(.player, playsExit: false)
            gameSession.playerSeat = nil
            if seated != nil {
                game.scripts.runtime?.queueFurnitureEvent(
                    sitting: false, actor: .player, furniture: occupancy.seat.furniture
                )
            }
        }

        public func moveFurnitureActor(_ actor: ReferenceKey, to pose: FurniturePose) {
            if actor == .player {
                if let gameSession = game.gameSession {
                    seatPlayer(at: pose, gameSession: gameSession)
                }
            } else {
                game.streamer.restActor(actor, at: ReferenceTransformOverride(
                    position: pose.root, rotation: SIMD3(0, 0, pose.heading)
                ))
            }
        }

        /// The body's root goes on the pose and the eye on the idle's head bone.
        private func seatPlayer(at pose: FurniturePose, gameSession: any GameSessionPort) {
            let root = MatrixMath.placement(
                position: pose.root, rotation: SIMD3(0, 0, pose.heading), scale: 1
            )
            let head = game.idleWorld.idles.idleBone(
                of: .player,
                named: DialogueCamera.headBoneName
            )
            gameSession.seatPlayer(at: root, head: head)
        }

        /// An NPC rests on the seat and activates it, so its scripts get `OnActivate`. The
        /// player's own activation already did; the frame step keeps the player seated.
        public func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
            let seat = occupancy.seat
            if actor == .player, let gameSession = game.gameSession {
                seatPlayer(at: seat.seat.seatedPose, gameSession: gameSession)
            } else if actor != .player {
                game.streamer.restActor(actor, at: ReferenceTransformOverride(
                    position: seat.seat.root, rotation: SIMD3(0, 0, seat.seat.heading)
                ))
                game.scripts.bridge?.activate(seat.furniture, by: actor, togglesOpen: false)
            }
            owner.holdAssociatedSpell(of: seat.seat, on: actor, while: true)
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
            owner.holdAssociatedSpell(of: occupancy.seat.seat, on: actor, while: false)
            game.idleWorld.idles.leaveFurniture(actor)
            game.scripts.runtime?.queueFurnitureEvent(
                sitting: false, actor: actor, furniture: occupancy.seat.furniture
            )
        }

        public func furnitureMotion(of actor: ReferenceKey) -> FurnitureMotionSample? {
            guard let playing = game.idleWorld.idles.rootMotion(of: actor) else { return nil }
            let (motion, elapsed) = playing
            return FurnitureMotionSample(
                offset: motion.offset(at: elapsed), yaw: motion.yaw(at: elapsed),
                endOffset: motion.offset(at: motion.duration),
                endYaw: motion.yaw(at: motion.duration),
                isFinished: elapsed >= motion.duration
            )
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
    }
}

extension AISeatingAdapter {
    func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
        poses.placeSeated(actor, in: occupancy)
    }

    func placeStanding(_ actor: ReferenceKey, from occupancy: FurnitureOccupancy) {
        poses.placeStanding(actor, from: occupancy)
    }

    func furnitureMotion(of actor: ReferenceKey) -> FurnitureMotionSample? {
        poses.furnitureMotion(of: actor)
    }

    func moveFurnitureActor(_ actor: ReferenceKey, to pose: FurniturePose) {
        poses.moveFurnitureActor(actor, to: pose)
    }

    func finishStanding(_ actor: ReferenceKey, at pose: FurniturePose) {
        poses.finishStanding(actor, at: pose)
    }
}
