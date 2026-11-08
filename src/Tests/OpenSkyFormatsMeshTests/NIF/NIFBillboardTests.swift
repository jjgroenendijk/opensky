// Billboard nodes turn by their nif.xml mode, and the node animator turns them in a
// mesh so their children follow (docs/formats/nif-sequences.md#billboard-nodes).

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFBillboardTests {
    private static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    private static func expectClose(_ got: SIMD3<Float>, _ want: SIMD3<Float>) {
        #expect(simd_length(got - want) < 1e-4, "\(got) != \(want)")
    }

    private static func turned(
        mode: UInt16, rotation: simd_quatf = identity, viewer: NIFBillboard.Viewer
    ) throws -> simd_quatf {
        try #require(NIFBillboard.rotation(
            mode: mode, rotation: rotation, origin: .zero, viewer: viewer
        ))
    }

    @Test(arguments: [UInt16(4), 12])
    func aRigidFaceCentreModeTurnsPlusZToTheEyeWithCameraUp(mode: UInt16) throws {
        let viewer = NIFBillboard.Viewer(eye: [100, 0, 0], forward: [0, 1, 0], up: [0, 0, 1])
        let rotation = try Self.turned(mode: mode, viewer: viewer)
        Self.expectClose(rotation.act([0, 0, 1]), [1, 0, 0])
        Self.expectClose(rotation.act([0, 1, 0]), [0, 0, 1])
    }

    @Test(arguments: [UInt16(0), 2])
    func aFaceCameraModeTurnsPlusZAgainstTheViewDirection(mode: UInt16) throws {
        let viewer = NIFBillboard.Viewer(eye: [50, -100, 0], forward: [0, 1, 0], up: [0, 0, 1])
        let rotation = try Self.turned(mode: mode, viewer: viewer)
        Self.expectClose(rotation.act([0, 0, 1]), [0, -1, 0])
    }

    @Test(arguments: [UInt16(0), 3])
    func aMinimisedModeTakesTheShortestTurnAndKeepsItsRoll(mode: UInt16) throws {
        let viewer = NIFBillboard.Viewer(eye: [100, 0, 0], forward: [-1, 0, 0], up: [0, 0, 1])
        let rotation = try Self.turned(mode: mode, viewer: viewer)
        Self.expectClose(rotation.act([0, 0, 1]), [1, 0, 0])
        // The shortest turn from +Z to +X is about +Y, so +Y stays put.
        Self.expectClose(rotation.act([0, 1, 0]), [0, 1, 0])
    }

    @Test func modeNineTurnsLikeModeOneFromItsLowBits() throws {
        let authored = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let viewer = NIFBillboard.Viewer(eye: [0, 100, 50], forward: nil, up: [0, 0, 1])
        let nine = try Self.turned(mode: 9, rotation: authored, viewer: viewer)
        let one = try Self.turned(mode: 1, rotation: authored, viewer: viewer)
        Self.expectClose(nine.act([0, 0, 1]), one.act([0, 0, 1]))
    }

    @Test func rotateAboutUpKeepsTheOwnPlusYAxis() throws {
        // Authored 90 degrees about X, so the node's own +Y is world +Z.
        let authored = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let viewer = NIFBillboard.Viewer(eye: [0, 100, 50], forward: nil, up: [0, 0, 1])
        let rotation = try Self.turned(mode: 1, rotation: authored, viewer: viewer)
        Self.expectClose(rotation.act([0, 1, 0]), [0, 0, 1])
        Self.expectClose(rotation.act([0, 0, 1]), [0, 1, 0])
    }

    @Test func bethesdaRotateAboutUpTurnsAboutTheOwnPlusZ() throws {
        let viewer = NIFBillboard.Viewer(eye: [100, 0, 30], forward: nil, up: [0, 0, 1])
        let rotation = try Self.turned(mode: 5, viewer: viewer)
        Self.expectClose(rotation.act([0, 0, 1]), [0, 0, 1])
        Self.expectClose(rotation.act([0, -1, 0]), [1, 0, 0])
    }

    @Test func anEyeOnTheNodeLeavesItAsAuthored() {
        let viewer = NIFBillboard.Viewer(eye: .zero, forward: nil, up: [0, 0, 1])
        #expect(NIFBillboard.rotation(
            mode: 4, rotation: Self.identity, origin: .zero, viewer: viewer
        ) == nil)
    }

    @Test func theViewerMovesIntoTheMeshSpace() {
        let placement = float4x4(columns: (
            [0, 2, 0, 0], [-2, 0, 0, 0], [0, 0, 2, 0], [10, 0, 0, 1]
        ))
        let viewer = NIFBillboard.Viewer(eye: [10, 20, 0], forward: [0, 1, 0], up: [0, 0, 1])
            .local(to: placement)
        Self.expectClose(viewer.eye, [10, 0, 0])
        Self.expectClose(viewer.forward ?? .zero, [1, 0, 0])
        Self.expectClose(viewer.up, [0, 0, 1])
    }

    @Test func theStaticModelDrawsTheShapesUnderABillboard() throws {
        var billboard = NIFFixture.niNode(children: [2])
        billboard.appendUInt16(4)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSFadeNode", NIFFixture.niNode(children: [1])),
            .init("NiBillboardNode", billboard),
            .init("BSTriShape", NIFFixture.staticTriangleShape(shaderPropertyRef: 3)),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty())
        ]))
        #expect(try file.model().meshes.count == 1)
    }

    /// A root turned 90 degrees about Z, a billboard at x 10 under it, and a child below.
    private static func animator(mode: UInt16) throws -> NIFNodeAnimator {
        var billboard = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 1, translation: [10, 0, 0]),
            children: [2]
        )
        billboard.appendUInt16(mode)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(
                    nameIndex: 0, rotationRows: [0, -1, 0, 1, 0, 0, 0, 0, 1]
                ),
                children: [1]
            )),
            .init("NiBillboardNode", billboard),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(nameIndex: 2)))
        ], strings: ["Root", "Glow", "Card"]))
        return try NIFNodeAnimator(animation: NIFNodeAnimation(file: file))
    }

    @Test func theAnimatorTurnsABillboardAndItsChildFollows() throws {
        var animator = try Self.animator(mode: 4)
        #expect(animator.animation.nodes.map(\.billboardMode) == [nil, 4, nil])
        #expect(animator.animation.billboardNodes == [1])
        animator.face(NIFBillboard.Viewer(eye: [100, 10, 0], forward: nil, up: [0, 0, 1]))
        let card = animator.modelTransform(of: 2)
        Self.expectClose(card.translation, [0, 10, 0])
        Self.expectClose(card.rotation.act([0, 0, 1]), [1, 0, 0])
        Self.expectClose(card.rotation.act([0, 1, 0]), [0, 0, 1])
        #expect(animator.locals[1].rotation == Self.identity)
    }
}
