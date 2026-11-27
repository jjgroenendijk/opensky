public import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

extension AIWorldAdapter {
    /// Answers the furniture, package, and perception worlds by forwarding to the narrow
    /// parts, so the coordinators reach only the part they need.
    public final class Worlds {
        let seating: AISeatingAdapter
        let perceptionSense: AIPerceptionSenseAdapter
        let navigation: AINavigationAdapter
        let packageMoves: AIPackageMovesAdapter
        let packageState: AIPackageStateAdapter
        let packageActs: AIPackageActsAdapter
        let offscreenHomes = OffscreenHomeCache()

        init(_ adapter: AIWorldAdapter) {
            seating = adapter.seating
            perceptionSense = adapter.perceptionSense
            navigation = adapter.navigation
            packageMoves = adapter.packageMoves
            packageState = adapter.packageState
            packageActs = adapter.packageActs
        }

        public func packageSeat(
            in furniture: ReferenceKey, actor: ReferenceKey, animation: UInt16
        ) -> PackageSeat? {
            seating.packageSeat(in: furniture, actor: actor, animation: animation)
        }

        public func packageSandboxSeat(
            for actor: ReferenceKey, in request: SandboxSeatRequest
        ) -> PackageSeat? {
            seating.packageSandboxSeat(for: actor, in: request)
        }

        public func seatPackageActor(_ actor: ReferenceKey, in seat: PackageSeat) {
            seating.seatPackageActor(actor, in: seat)
        }

        public func turnPackageActor(
            _ actor: ReferenceKey, toHeading heading: Float, within tolerance: Float
        ) -> Float? {
            seating.turnPackageActor(actor, toHeading: heading, within: tolerance)
        }

        public func unseatPackageActor(_ actor: ReferenceKey, from seat: PackageSeat?) {
            seating.unseatPackageActor(actor, from: seat)
        }

        public func packageActorSeat(_ actor: ReferenceKey) -> PackageSeat? {
            seating.game.furniture.occupancies[actor]?.seat
        }

        public func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
            seating.furnitureSeats(of: furniture)
        }

        public func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
            seating.furnitureActorPosition(actor)
        }

        public func isFurnitureInUse(
            _ furniture: ReferenceKey,
            marker: Int?,
            ignoringReserved: Bool
        ) -> Bool {
            seating.isFurnitureInUse(furniture, marker: marker, ignoringReserved: ignoringReserved)
        }

        public func setSittingRotation(degrees: Float) {
            seating.setSittingRotation(degrees: degrees)
        }

        public func lightLevel(at position: SIMD3<Float>) -> Float {
            perceptionSense.lightLevel(at: position)
        }

        public func perceptionHasLineOfSight(
            from origin: SIMD3<Float>,
            to destination: SIMD3<Float>
        ) -> Bool {
            perceptionSense.perceptionHasLineOfSight(from: origin, to: destination)
        }

        public func mountPackageActor(_ rider: ReferenceKey) -> ReferenceKey? {
            navigation.mountPackageActor(rider)
        }

        public func dismountPackageActor(_ rider: ReferenceKey) {
            navigation.dismountPackageActor(rider)
        }

        public var camera: AICameraPose? {
            navigation.camera
        }

        public func actorCandidates() -> [AIActorCandidate] {
            navigation.actorCandidates()
        }

        public func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit? {
            navigation.nearestCollisionHit(ray: ray)
        }

        public func residentActor(for reference: FormID) -> ReferenceKey? {
            navigation.residentActor(for: reference)
        }

        public func moveActor(
            _ actor: ReferenceKey,
            to point: SIMD3<Float>
        ) -> NPCMoveCommandResult {
            PackageSteps(owner: self).moveActor(actor, to: point)
        }

        public func stopActor(_ actor: ReferenceKey) -> Bool {
            navigation.stopActor(actor)
        }

        public func isHostile(_ actor: ReferenceKey) -> Bool {
            navigation.isHostile(actor)
        }

        public func setHostile(_ hostile: Bool, actor: ReferenceKey) {
            navigation.setHostile(hostile, actor: actor)
        }

        public var animationClips: ActorClipLoader? {
            navigation.animationClips
        }

        public var packageDrivesPlayer: Bool {
            packageMoves.packageDrivesPlayer
        }

        public func packagePlace(
            of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
        ) -> PackagePlace? {
            PackageSteps(owner: self).packagePlace(
                of: location,
                actor: actor,
                aliasQuest: aliasQuest
            )
        }

        public func packageActorHoldsIdleMarker(_ actor: ReferenceKey) -> Bool {
            packageMoves.packageActorHoldsIdleMarker(actor)
        }

        public func packageActorFlies(_ actor: ReferenceKey) -> Bool {
            packageMoves.packageActorFlies(actor)
        }

        public func packageSandboxActivityEnded(_ activity: SandboxActivity, actor: ReferenceKey) {
            packageMoves.packageSandboxActivityEnded(activity, actor: actor)
        }

        public func movePackageActor(_ move: PackageMove) -> PackageMoveResult {
            packageMoves.movePackageActor(move)
        }

        public func packageAliasStacks() -> [ReferenceKey: PackageAliasStack] {
            packageMoves.packageAliasStacks()
        }

        public func packagePatrolPath(
            from start: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
        ) -> [SIMD3<Float>]? {
            packageMoves.packagePatrolPath(from: start, actor: actor, aliasQuest: aliasQuest)
        }

        public func packageProcedure(_ event: PackageScriptEvent) {
            PackageSteps(owner: self).packageProcedure(event)
        }

        public func packageLeveledRoll(of actor: ReferenceKey, base: FormID) -> LeveledRoll? {
            packageState.packageLeveledRoll(of: actor, base: base)
        }

        public func packageResidents() -> [RuntimeReferenceEntry]? {
            packageState.packageResidents()
        }

        public var packageClock: GameClock? {
            packageState.packageClock
        }

        public func packageConditionContext(clock: GameClock) -> ConditionContext {
            packageState.packageConditionContext(clock: clock)
        }

        public func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
            packageMoves.packageActorPosition(actor)
        }

        public func packageActorGait(_ actor: ReferenceKey) -> LocomotionGait? {
            packageState.packageActorGait(actor)
        }

        public func isWithin(_ location: Package.Location, actor: ReferenceKey) -> Bool {
            packageState.isWithin(location, actor: actor)
        }

        public func packageActorActivity(_ actor: ReferenceKey) -> PackageActorActivity {
            packageState.packageActorActivity(actor)
        }

        public func isAIDisabled(_ actor: ReferenceKey) -> Bool {
            packageState.isAIDisabled(actor)
        }

        public func packageMoverHasRoom(for actor: ReferenceKey) -> Bool {
            packageState.packageMoverHasRoom(for: actor)
        }

        public func packageReference(
            _ target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
        ) -> ReferenceKey? {
            packageActs.packageReference(target, actor: actor, aliasQuest: aliasQuest)
        }

        public func stopPackageActor(_ actor: ReferenceKey) {
            packageActs.stopPackageActor(actor)
        }

        public func packageAction(
            _ action: PackageAction,
            actor: ReferenceKey
        ) -> PackageActionResult {
            packageActs.packageAction(action, actor: actor)
        }

        public func activate(
            _ target: ReferenceKey,
            by actor: ReferenceKey
        ) -> PackageActionResult {
            packageActs.activate(target, by: actor)
        }

        public func packageSituations(of actors: [ReferenceKey])
            -> [ReferenceKey: PackageSituation]
        {
            packageActs.packageSituations(of: actors)
        }
    }
}

extension AIWorldAdapter.Worlds: PapyrusFurnitureBridge {}
extension AIWorldAdapter.Worlds: PackageWorld {}
extension AIWorldAdapter.Worlds: OffscreenScheduleWorld {}
extension AIWorldAdapter.Worlds: AINavigationWorld {}
extension AIWorldAdapter.Worlds: NPCAnimationWorld {}
extension AIWorldAdapter.Worlds: AIWorldPort {}

extension AIWorldAdapter.Worlds {
    /// Moves package actors and runs package procedures.
    struct PackageSteps {
        let owner: AIWorldAdapter.Worlds

        func moveActor(
            _ actor: ReferenceKey,
            to point: SIMD3<Float>
        ) -> NPCMoveCommandResult {
            let navigation = owner.navigation
            return navigation.moveActor(actor, to: point)
        }

        func packagePlace(
            of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
        ) -> PackagePlace? {
            let packageMoves = owner.packageMoves
            return packageMoves.packagePlace(of: location, actor: actor, aliasQuest: aliasQuest)
        }

        func packageProcedure(_ event: PackageScriptEvent) {
            let packageActs = owner.packageActs
            let packageMoves = owner.packageMoves
            if event.unlocksDoors {
                _ = packageActs.references.unlockOwnedDoors(of: event.actor)
            }
            packageMoves.packageProcedure(event)
        }
    }
}
