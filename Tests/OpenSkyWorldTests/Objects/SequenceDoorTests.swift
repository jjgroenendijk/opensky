// A sequence door: a gate whose one leaf rises 100 units in `Open` and falls in
// `Close`. Its rig, its motion and text keys, its coordinator, and its moving collision.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyPhysics
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
private final class FakeDoorWorld: SequenceDoorWorld {
    var doors: [CellSequenceDoor] = []
    var wantsOpen = false

    func residentSequenceDoors() -> [CellSequenceDoor] {
        doors
    }

    func sequenceDoorWantsOpen(_: UInt32) -> Bool {
        wantsOpen
    }
}

@MainActor
struct SequenceDoorTests {
    static func moved(_ offset: SIMD3<Float>) -> float4x4 {
        MatrixMath.placement(position: offset, rotation: .zero, scale: 1)
    }

    static func rig() throws -> SequenceDoorRig {
        let file = try NIFFile(data: SequenceDoorFixture.file())
        return try #require(try SequenceDoorRig(file: file))
    }

    @Test func theRigMovesTheLeafFromItsRest() throws {
        let rig = try Self.rig()
        #expect(rig.skeleton.boneNames == ["Leaf"])
        #expect(rig.leaf(ofBlock: 1) == 0)
        #expect(rig.leaf(ofBlock: 0) == nil)
        let closed = rig.leafTransforms(.close, at: rig.close.timing.stopTime)
        #expect(closed[0].columns.3 == SIMD4(10, 0, 0, 1))
        let open = rig.leafTransforms(.open, at: rig.open.timing.stopTime)
        #expect(open[0].columns.3 == SIMD4(10, 0, 100, 1))
        #expect(rig.leafDeltas(open)[0].columns.3 == SIMD4(0, 0, 100, 1))
    }

    @Test func aMeshWithoutBothSequencesIsNoDoor() throws {
        let file = try NIFFile(data: SequenceDoorFixture.file(withClose: false))
        #expect(try SequenceDoorRig(file: file) == nil)
    }

    @Test func theMotionOpensPassesItsKeysAndTurnsBack() throws {
        let rig = try Self.rig()
        var motion = SequenceDoorMotion(open: false, rig: rig)
        #expect(motion.phase == .closed)
        #expect(motion.step(wantsOpen: false, deltaTime: 1, rig: rig).isEmpty)
        #expect(motion.step(wantsOpen: true, deltaTime: 0.5, rig: rig)
            == ["start", "Sound: GateOpen"])
        #expect(motion.phase == .opening)
        #expect(motion.phase.openStateCode == 2)
        #expect(motion.step(wantsOpen: true, deltaTime: 1, rig: rig) == ["end"])
        #expect(motion.phase == .open)
        #expect(motion.phase.openStateCode == 1)

        _ = motion.step(wantsOpen: false, deltaTime: 0.25, rig: rig)
        #expect(motion.phase == .closing)
        #expect(motion.phase.openStateCode == 4)
        _ = motion.step(wantsOpen: true, deltaTime: 0, rig: rig)
        #expect(motion.phase == .opening)
        #expect(abs(motion.time - 0.75) < 0.0001, "turned back 25% from open")
    }

    @Test func theCoordinatorPosesKeepsMotionAcrossARebuildAndDropsADepartedDoor() throws {
        let rig = try Self.rig()
        let world = FakeDoorWorld()
        let first = CellSequenceDoor(
            reference: 0x20, modelPath: "Gate.nif", rig: rig, pose: PlayerPoseBuffer()
        )
        world.doors = [first]
        let doors = SequenceDoorCoordinator(world: world)
        #expect(doors.sync().isEmpty)
        _ = doors.tick(deltaTime: 0)
        #expect(first.pose.bones.first?.translation == SIMD3(10, 0, 0))
        #expect(doors.openStateCode(of: 0x20) == 3)

        world.wantsOpen = true
        #expect(doors.openStateCode(of: 0x20) == 2, "a move asked for reads as started")
        let opening = doors.tick(deltaTime: 0.5)
        #expect(opening.prefix(2) == [
            .textKey("start", reference: 0x20), .textKey("Sound: GateOpen", reference: 0x20)
        ])
        guard case let .setLeaves(leaves, 0x20)? = opening.last else {
            Issue.record("no leaves for the moving door")
            return
        }
        #expect(leaves?.first?.columns.3 == SIMD4(0, 0, 50, 1))

        let rebuilt = CellSequenceDoor(
            reference: 0x20, modelPath: "Gate.nif", rig: rig, pose: PlayerPoseBuffer()
        )
        world.doors = [rebuilt]
        #expect(doors.sync().isEmpty)
        _ = doors.tick(deltaTime: 1)
        #expect(doors.rows == [
            SequenceDoorRow(reference: 0x20, modelPath: "Gate.nif", phase: .open)
        ])
        #expect(rebuilt.pose.bones.first?.translation == SIMD3(10, 0, 100))

        world.doors = []
        #expect(doors.sync() == [.setLeaves(nil, reference: 0x20)])
        #expect(doors.openStateCode(of: 0x20) == nil)
    }

    @Test func theLeafCollisionMovesAndTheFrameStays() {
        let placement = MatrixMath.placement(position: [1000, 0, 0], rotation: .zero, scale: 1)
        func box(at center: SIMD3<Float>) -> StaticCollisionShape {
            StaticCollisionShape.placed(
                reference: FormID(0x20),
                transform: placement * Self.moved(center),
                geometry: .box(halfExtents: [5, 5, 5])
            )[0]
        }
        let door = CellDoorCollision(
            reference: FormID(0x20), placement: placement,
            fixed: [box(at: [-50, 0, 0])], leaves: [[box(at: [10, 0, 0])]]
        )
        let everywhere = ModelBounds(
            min: SIMD3(repeating: -10000), max: SIMD3(repeating: 10000)
        )
        let raised = door.shapes(
            leafDeltas: [Self.moved([0, 0, 100])], overlapping: everywhere
        )
        #expect(raised.map(\.transform.columns.3) == [
            SIMD4(950, 0, 0, 1), SIMD4(1010, 0, 100, 1)
        ])
        let atRest = ModelBounds(min: [1000, -10, -10], max: [1020, 10, 10])
        #expect(door.shapes(leafDeltas: [Self.moved([0, 0, 100])], overlapping: atRest)
            .isEmpty)
        #expect(door.shapes(leafDeltas: nil, overlapping: atRest).count == 1)
    }
}
