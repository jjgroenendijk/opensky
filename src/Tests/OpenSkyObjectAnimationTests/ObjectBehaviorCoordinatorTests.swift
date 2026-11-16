// The object behaviour coordinator without a graph and across a cell rebuild, and the
// project path rules.

import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyObjectAnimation
import OpenSkyWorldInterface
import Testing

private final class EmptyObjectWorld: ObjectBehaviorWorld {
    func residentAnimatedObjects() -> [CellAnimatedObject] {
        []
    }

    func objectGraphFired(_: String, from _: UInt32) {}

    func animationWaitFinished(token _: UInt64, fired _: Bool) {}
}

private final class RebuiltObjectWorld: ObjectBehaviorWorld {
    var objects: [CellAnimatedObject] = []
    var finished: [(token: UInt64, fired: Bool)] = []

    func residentAnimatedObjects() -> [CellAnimatedObject] {
        objects
    }

    func objectGraphFired(_: String, from _: UInt32) {}

    func animationWaitFinished(token: UInt64, fired: Bool) {
        finished.append((token, fired))
    }
}

@MainActor
struct ObjectBehaviorCoordinatorTests {
    /// A rebuilt cell brings a new pose buffer. The graph keeps running, so a script that
    /// waits for its end event is not dropped, as the Ratway bridge's wait was.
    @Test func aRebuiltCellKeepsTheGraphAndItsWaits() throws {
        let world = RebuiltObjectWorld()
        let asset = try BehaviorProjectFixture.asset()
        world.objects = [CellAnimatedObject(
            reference: 0x10,
            asset: asset,
            pose: SkinnedPoseBuffer()
        )]
        let objects = ObjectBehaviorCoordinator(world: world, files: { nil })
        objects.sync()
        let first = try #require(objects.running[0x10])
        let token = try #require(objects.awaitEvent("Trans02", on: 0x10))
        let rebuilt = SkinnedPoseBuffer()
        world.objects = [CellAnimatedObject(reference: 0x10, asset: asset, pose: rebuilt)]
        objects.sync()
        let kept = try #require(objects.running[0x10])
        #expect(kept === first)
        #expect(kept.object.pose === rebuilt)
        #expect(world.finished.isEmpty)
        world.objects = []
        objects.sync()
        #expect(world.finished.map(\.token) == [token])
        #expect(world.finished.map(\.fired) == [false])
    }

    @Test func anObjectWithoutAGraphTakesNoEventAndNoWait() {
        let world = EmptyObjectWorld()
        let objects = ObjectBehaviorCoordinator(world: world, files: { nil })
        objects.sync()
        objects.tick(deltaTime: 1 / 60)
        #expect(!objects.send("Trigger", to: 0x10))
        #expect(objects.awaitEvent("Done", on: 0x10) == nil)
        #expect(!objects.setVariable(.bool(true), named: "bOpen", on: 0x10))
        #expect(objects.variable(named: "bOpen", on: 0x10) == nil)
        #expect(objects.worldBone(of: 0x10, named: "Blade") == nil)
        #expect(objects.rows.isEmpty)
    }

    @Test func laterPathsAreRelativeToTheProjectFolder() {
        let project = "meshes\\traps\\swingingblade\\trapbladeswinging01.hkx"
        let folder = BehaviorProjectAsset.folder(of: project)
        #expect(folder == "meshes\\traps\\swingingblade")
        #expect(BehaviorProjectAsset.join(folder, "Characters/Character00.hkx")
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
