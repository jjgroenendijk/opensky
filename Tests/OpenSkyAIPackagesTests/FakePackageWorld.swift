// A package session for the coordinator tests: it records walks, stops, acts and
// fragments, and answers every question with a setting the test controls.

@testable import OpenSkyAIPackages
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd

@MainActor
final class FakePackageWorld: PackageWorld {
    var residents: [RuntimeReferenceEntry]? = []
    var packageClock: GameClock? = GameClock(hour: 9)
    private(set) var contextReads = 0
    private(set) var moves: [SIMD3<Float>] = []
    private(set) var gaits: [LocomotionGait?] = []
    private(set) var movers: [ReferenceKey] = []
    var horse: ReferenceKey?
    var moverSlotsFull = false
    var drivesPlayer = false
    var activity: PackageActorActivity = .free
    var hasRoom = true
    var holdsIdleMarker = false
    private(set) var stops: [ReferenceKey] = []
    private(set) var scriptEvents: [PackageScriptEvent.Kind] = []
    private(set) var actions: [PackageAction] = []
    static let place = SIMD3<Float>(100, 0, 0)
    static let patrol = [SIMD3<Float>(10, 0, 0), SIMD3<Float>(20, 0, 0)]

    func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        .zero
    }

    func packagePlace(
        of location: Package.Location, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackagePlace? {
        location.formID == FormID(0x700) ? PackagePlace(point: Self.place, radius: 0) : nil
    }

    func movePackageActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct _: Bool, gait: LocomotionGait?
    ) -> PackageMoveResult {
        gaits.append(gait)
        moves.append(point)
        movers.append(actor)
        return moverSlotsFull ? .busy : .started
    }

    func packagePatrolPath(
        from _: Package.Target, actor _: ReferenceKey, aliasQuest _: FormID?
    ) -> [SIMD3<Float>]? {
        Self.patrol
    }

    func packageAction(_ action: PackageAction, actor _: ReferenceKey) -> PackageActionResult {
        actions.append(action)
        return .done
    }

    func mountPackageActor(_: ReferenceKey) -> ReferenceKey? {
        horse
    }

    func packageProcedure(_ event: PackageScriptEvent) {
        scriptEvents.append(event.kind)
    }

    func packageActorActivity(_: ReferenceKey) -> PackageActorActivity {
        activity
    }

    func packageMoverHasRoom(for _: ReferenceKey) -> Bool {
        hasRoom
    }

    func packageActorHoldsIdleMarker(_: ReferenceKey) -> Bool {
        holdsIdleMarker
    }

    func stopPackageActor(_ actor: ReferenceKey) {
        stops.append(actor)
    }

    func packageResidents() -> [RuntimeReferenceEntry]? {
        residents
    }

    var packageDrivesPlayer: Bool {
        drivesPlayer
    }

    func packageConditionContext(clock _: GameClock) -> ConditionContext {
        contextReads += 1
        return ConditionContext()
    }
}
