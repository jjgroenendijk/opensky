public import OpenSkyAIPackages
public import OpenSkyFormatsESM
public import OpenSkyPerception
public import OpenSkyPerceptionInterface
public import OpenSkyPlayer
public import OpenSkyWorldInterface
import simd

extension AIWorldAdapter {
    /// Answers the furniture coordinator and the player's stand request from the seating part.
    public final class FurnitureWorlds {
        let seating: AISeatingAdapter

        init(_ adapter: AIWorldAdapter) {
            seating = adapter.seating
        }

        public func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
            seating.furnitureSeats(of: furniture)
        }

        public func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
            seating.furnitureActorPosition(actor)
        }

        public func furnitureIsSpecial(_ furniture: ReferenceKey) -> Bool {
            seating.furnitureIsSpecial(furniture)
        }

        public func furnitureOwnerAllows(_ actor: ReferenceKey, _ furniture: ReferenceKey) -> Bool {
            seating.furnitureOwnerAllows(actor, furniture)
        }

        public func furnitureActorTraits(_ actor: ReferenceKey) -> FurnitureActorTraits {
            seating.furnitureActorTraits(actor)
        }

        public func furnitureActorHasKeyword(_ actor: ReferenceKey, _ keyword: FormID) -> Bool {
            seating.furnitureActorHasKeyword(actor, keyword)
        }

        public func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
            seating.placeSeated(actor, in: occupancy)
        }

        public func placeStanding(_ actor: ReferenceKey, from occupancy: FurnitureOccupancy) {
            seating.placeStanding(actor, from: occupancy)
        }

        public func furnitureExitIsLoading(_ actor: ReferenceKey) -> Bool {
            seating.furnitureExitIsLoading(actor)
        }

        public func furnitureMotion(of actor: ReferenceKey) -> FurnitureMotionSample? {
            seating.furnitureMotion(of: actor)
        }

        public func moveFurnitureActor(_ actor: ReferenceKey, to pose: FurniturePose) {
            seating.moveFurnitureActor(actor, to: pose)
        }

        public func finishStanding(_ actor: ReferenceKey, at pose: FurniturePose) {
            seating.finishStanding(actor, at: pose)
        }

        public func residentFurniture() -> [ReferenceKey] {
            seating.residentFurniture()
        }

        public func turnSeatedPlayerView(toYaw yaw: Float) {
            seating.turnSeatedPlayerView(toYaw: yaw)
        }

        public func playerAskedToStand() {
            seating.playerAskedToStand()
        }
    }

    /// Answers the perception pass from the perception sense part.
    public final class PerceptionWorlds {
        let perceptionSense: AIPerceptionSenseAdapter

        init(_ adapter: AIWorldAdapter) {
            perceptionSense = adapter.perceptionSense
        }

        public func perceptionHasLineOfSight(
            from origin: SIMD3<Float>,
            to destination: SIMD3<Float>
        ) -> Bool {
            perceptionSense.perceptionHasLineOfSight(from: origin, to: destination)
        }

        public func perceptionCandidates() -> [PerceptionCandidate] {
            perceptionSense.perceptionCandidates()
        }

        public func perceptionCandidates(
            isDue: (ReferenceKey, SIMD3<Float>) -> Bool
        ) -> (present: [ReferenceKey], fresh: [PerceptionCandidate]) {
            perceptionSense.perceptionCandidates(isDue: isDue)
        }

        public func perceptionTargets() -> [PerceptionTarget] {
            perceptionSense.perceptionTargets()
        }

        public func perceptionActorPairs() -> [DetectionPairKey] {
            perceptionSense.perceptionActorPairs()
        }
    }
}

extension AIWorldAdapter.FurnitureWorlds: FurnitureWorld {}
extension AIWorldAdapter.FurnitureWorlds: PlayerFurnitureDriving {}
extension AIWorldAdapter.PerceptionWorlds: PerceptionSessionWorld {}
