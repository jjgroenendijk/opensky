// Env-gated check over the user's install: the view ray in front of a vanilla load
// door meets the door, not the wall behind it. Run with
// `make test PLAN=RealData T='DoorPickRealDataTests/innDoorStopsTheViewRay()'`.

@testable import OpenSkyCells
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyObjectAnimation
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
import OpenSkyTagsTesting
import OpenSkyWorldInterface
import simd
import Testing

@Suite(.tags(.gpu))
struct DoorPickRealDataTests {
    /// The Sleeping Giant Inn's front door in Riverwood, and the arrival point in front of it.
    private static let innDoor = FormID(0x13424)
    private static let arrival = SIMD3<Float>(23259.771, -44476.164, -8.255)

    @Test(.enabled(if: RealDataEnvironment.canRender), .tags(.smoke))
    func innDoorStopsTheViewRay() throws {
        let builder = try RealDataInstall.load().sceneBuilder(readsLooseFiles: true)
        let scene = try builder.buildScene(worldspaceEditorID: "Tamriel", gridX: 5, gridY: -11)
        let door = try #require(scene.doors.first { $0.reference == Self.innDoor })
        let eye = Self.arrival + SIMD3(0, 0, 112)
        let target = SIMD3(door.position.x, door.position.y, eye.z)
        let ray = try #require(InteractionRay(origin: eye, direction: target - eye))
        let shapes = scene.staticCollision.candidates(overlapping: ray.bounds)
            + scene.doorCollision.flatMap { $0.shapes(leafDeltas: nil, overlapping: ray.bounds) }
        let hit = try #require(InteractionRaycaster.nearestHit(ray: ray, shapes: shapes))
        #expect(hit.reference == Self.innDoor)
        #expect(hit.distance < simd_distance(eye, target))
    }
}
