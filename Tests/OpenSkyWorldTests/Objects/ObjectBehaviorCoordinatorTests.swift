// The object behaviour coordinator without a graph, and the project path rules.

@testable import OpenSkyWorld
import Testing

private final class EmptyObjectWorld: ObjectBehaviorWorld {
    func residentAnimatedObjects() -> [CellAnimatedObject] {
        []
    }
}

@MainActor
struct ObjectBehaviorCoordinatorTests {
    @Test func anObjectWithoutAGraphTakesNoEventAndNoWait() {
        let world = EmptyObjectWorld()
        let objects = ObjectBehaviorCoordinator()
        objects.world = world
        objects.sync()
        objects.tick(deltaTime: 1 / 60)
        #expect(!objects.send("Trigger", to: 0x10))
        #expect(objects.awaitEvent("Done", on: 0x10) == nil)
        #expect(objects.rows.isEmpty)
    }

    @Test func laterPathsAreRelativeToTheProjectFolder() {
        let project = "meshes\\traps\\swingingblade\\trapbladeswinging01.hkx"
        let folder = ObjectBehaviorAsset.folder(of: project)
        #expect(folder == "meshes\\traps\\swingingblade")
        #expect(ObjectBehaviorAsset.join(folder, "Characters/Character00.hkx")
            == "meshes\\traps\\swingingblade\\characters\\character00.hkx")
    }

    @Test func theReadoutNamesTheSelectedObject() {
        let row = ObjectAnimationRow(
            reference: 0xABC, project: "meshes\\traps\\blade.hkx",
            events: ["Trigger", "Reset"], activeState: "Idle"
        )
        let text = ObjectAnimationReadout.text(rows: [row], selected: 0xABC, last: "-")
        #expect(text.contains("00000ABC blade.hkx"))
        #expect(text.contains("Events: Trigger, Reset"))
        #expect(ObjectAnimationReadout.text(rows: [], selected: nil, last: "-")
            .hasPrefix("No animated objects"))
    }
}
