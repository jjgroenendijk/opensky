// CellStreamer across worldspaces: a switch drops the old exterior, queues the
// change on the build queue, and drops results built for the old worldspace.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

private typealias Fixture = CellStreamerFixture

@MainActor
struct CellStreamerWorldspaceTests {
    private let solstheim = "DLC2SolstheimWorld"

    private func camera() -> SceneCamera {
        SceneCamera.teleport(placement: .init(position: Fixture.center, rotation: .zero))
    }

    @Test
    func enteringAWorldspaceDropsTheOldExterior() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        var changes: [String] = []
        streamer.onWorldspaceChanged.add { changes.append($0) }
        streamer.update(cameraPosition: Fixture.center)
        runner.complete(
            Fixture.coordinate(0, 0), worldspace: "Tamriel",
            with: .success(Fixture.cellScene(meshKeys: ["meshes\\rock.nif"]))
        )
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.composedCellCount == 1)

        streamer.enterWorldspace(solstheim, camera: camera())
        #expect(streamer.worldspaceEditorID == solstheim)
        #expect(runner.enqueuedWorldspaces == [solstheim])
        #expect(streamer.composedCellCount == 0)
        #expect(runner.evictedMeshKeys.contains { $0.contains("meshes\\rock.nif") })
        #expect(changes == [solstheim])
    }

    @Test
    func aResultFromTheOldWorldspaceIsDropped() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)
        streamer.enterWorldspace(solstheim, camera: camera())
        runner.complete(
            Fixture.coordinate(0, 0), worldspace: "Tamriel", with: .success(Fixture.cellScene())
        )
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.composedCellCount == 0)

        streamer.update(cameraPosition: Fixture.center)
        runner.complete(
            Fixture.coordinate(0, 0), worldspace: solstheim, with: .success(Fixture.cellScene())
        )
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.composedCellCount == 1)
    }

    @Test
    func theSameWorldspaceIsStillAReset() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.enterWorldspace("Tamriel", camera: camera())
        #expect(streamer.worldspaceEditorID == "Tamriel")
        #expect(runner.enqueuedWorldspaces == ["Tamriel"])
    }

    @Test
    func aDoorIntoAnotherWorldspaceSwitchesTheExterior() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 0)
        streamer.update(cameraPosition: Fixture.center)
        runner.complete(
            Fixture.coordinate(0, 0), worldspace: "Tamriel", with: .success(Fixture.cellScene())
        )
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.requestDoorTransition(from: FormID(0x10)))

        let placement = PlacedReference.Placement(position: Fixture.center, rotation: .zero)
        var transition = DoorTransition(
            sourceDoor: FormID(0x10),
            destinationDoor: FormID(0x20),
            destinationPlacement: placement,
            scene: Fixture.cellScene(location: .exterior(Fixture.coordinate(0, 0)))
        )
        transition.worldspaceEditorID = "WhiterunWorld"
        runner.completeDoorTransition(from: FormID(0x10), with: .success(transition))
        streamer.update(cameraPosition: Fixture.center)
        #expect(streamer.worldspaceEditorID == "WhiterunWorld")
        #expect(streamer.composedCellCount == 1)
        // The build half switched while it built the door; no second change is queued.
        #expect(runner.enqueuedWorldspaces.isEmpty)
    }
}
