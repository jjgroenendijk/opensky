// A placed mesh's free-running node controllers pose its own copy: the moved node is a
// bone, and the coordinator publishes it on the mesh's clock.

import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyObjectAnimation
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
private final class FakeNodeWorld: NodeControllerWorld {
    var meshes: [CellNodeAnimation] = []
    var nodeControllerViewer: NIFBillboard.Viewer?

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

    @Test func aBillboardIsABoneThatTurnsToTheCamera() throws {
        var glow = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 1, translation: [0, 0, 50]),
            children: []
        )
        glow.appendUInt16(4)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1]
            )),
            .init("NiBillboardNode", glow)
        ], strings: ["Root", "Glow"]))
        let rig = try #require(try NodeControllerRig(file: file))
        #expect(rig.skeleton.boneNames == ["Glow"])
        let world = FakeNodeWorld()
        world.nodeControllerViewer = NIFBillboard.Viewer(
            eye: [100, 0, 50], forward: [-1, 0, 0], up: [0, 0, 1]
        )
        let pose = PlayerPoseBuffer()
        world.meshes = [CellNodeAnimation(
            reference: 0x10, rig: rig, pose: pose,
            placement: MatrixMath.translation([0, 100, 0])
        )]
        let nodes = NodeControllerCoordinator(world: world)
        nodes.isEnabled = false
        nodes.sync()
        nodes.tick(deltaTime: 0.1)
        // The camera sits at mesh x 100, y -100, so +Z turns that way, also with the
        // "Animated objects" setting off.
        let bone = try #require(pose.snapshot.bones.first)
        let facing = bone.rotation.act([0, 0, 1])
        #expect(simd_length(facing - simd_normalize(SIMD3(1, -1, 0))) < 1e-4)
        #expect(nodes.nodes(of: 0x10)?.first?.controllers == ["NiBillboardNode mode 4"])
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
