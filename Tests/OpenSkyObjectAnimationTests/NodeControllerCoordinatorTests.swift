// A placed mesh's free-running node controllers pose its own copy: the moved node is a
// bone, and the coordinator publishes it on the mesh's clock.

import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyObjectAnimation
import simd
import Testing

@MainActor
private final class FakeNodeWorld: NodeControllerWorld {
    var meshes: [CellNodeAnimation] = []
    var nodeControllerViewer: SIMD3<Float>?

    func residentNodeAnimations() -> [CellNodeAnimation] {
        meshes
    }
}

@MainActor
struct NodeControllerCoordinatorTests {
    /// A root with a "Wheel" child whose controller slides it from x 0 to x 10 in a second.
    static func file(flags: UInt16) throws -> NIFFile {
        typealias Block = NIFFixture.Block
        let wheel = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 1, controllerRef: 2), children: []
        )
        return try NIFFile(data: NIFFixture.file(blocks: [
            Block("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1]
            )),
            Block("NiNode", wheel),
            Block("NiTransformController", NIFBlockFixture.transformController(
                flags: flags, interpolator: 3
            )),
            Block("NiTransformInterpolator", NIFFixture.transformInterpolator(data: 4)),
            Block("NiTransformData", NIFFixture.transformData(
                rotations: [], translations: [(0, .zero), (1, [10, 0, 0])]
            ))
        ], strings: ["Root", "Wheel"]))
    }

    @Test func theMovedNodeIsABoneThatTheCoordinatorPoses() throws {
        let rig = try #require(try NodeControllerRig(file: Self.file(flags: 0xC)))
        #expect(rig.skeleton.boneNames == ["Wheel"])
        let world = FakeNodeWorld()
        let pose = PlayerPoseBuffer()
        world.meshes = [CellNodeAnimation(
            reference: 0x10, rig: rig, pose: pose, placement: matrix_identity_float4x4
        )]
        let nodes = NodeControllerCoordinator(world: world)
        nodes.sync()
        nodes.tick(deltaTime: 0.5)
        let bone = try #require(pose.snapshot.bones.first)
        #expect(abs(bone.translation.x - 5) < 1e-4)
        #expect(nodes.nodes(of: 0x10)?.first?.name == "Wheel")
    }

    @Test func aMeshWithOnlyInactiveControllersGetsNoRig() throws {
        #expect(try NodeControllerRig(file: Self.file(flags: 0x4)) == nil)
    }

    @Test func aDepartedMeshStopsPlaying() throws {
        let rig = try #require(try NodeControllerRig(file: Self.file(flags: 0xC)))
        let world = FakeNodeWorld()
        world.meshes = [CellNodeAnimation(
            reference: 0x10, rig: rig, pose: PlayerPoseBuffer(), placement: matrix_identity_float4x4
        )]
        let nodes = NodeControllerCoordinator(world: world)
        nodes.sync()
        world.meshes = []
        nodes.sync()
        #expect(nodes.references.isEmpty)
    }
}
