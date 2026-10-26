// The node controllers over synthetic meshes: the active flag, look-at turns, lag
// bones, bone LOD, and a path's follow and bank (docs/formats/nif-controllers.md).

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFNodeAnimatorTests {
    private typealias Block = NIFFixture.Block

    private static func node(
        name: UInt32, controller: Int32 = -1, extraData: [Int32] = [],
        at translation: SIMD3<Float> = .zero, children: [Int32] = []
    ) -> Data {
        NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(
                nameIndex: name, extraDataRefs: extraData, controllerRef: controller,
                translation: translation
            ),
            children: children
        )
    }

    /// A transform controller, its interpolator, and its keys, at `first`.
    private static func moving(
        first: Int32, flags: UInt16 = 0xC, from: SIMD3<Float>, to: SIMD3<Float>
    ) -> [Block] {
        [
            Block("NiTransformController", NIFBlockFixture.transformController(
                flags: flags, interpolator: first + 1
            )),
            Block("NiTransformInterpolator", NIFFixture.transformInterpolator(data: first + 2)),
            Block(
                "NiTransformData",
                NIFFixture.transformData(rotations: [], translations: [(0, from), (1, to)])
            )
        ]
    }

    private static func animator(_ blocks: [Block], strings: [String]) throws -> NIFNodeAnimator {
        let file = try NIFFile(data: NIFFixture.file(blocks: blocks, strings: strings))
        return try NIFNodeAnimator(animation: NIFNodeAnimation(file: file))
    }

    @Test(arguments: [(UInt16(0xC), Float(5)), (UInt16(0x4), Float(0))])
    func onlyAnActiveControllerMovesItsNode(flags: UInt16, expectedX: Float) throws {
        var animator = try Self.animator(
            [Block("NiNode", Self.node(name: 0, controller: 1))]
                + Self.moving(first: 1, flags: flags, from: .zero, to: [10, 0, 0]),
            strings: ["Wheel"]
        )
        animator.step(deltaTime: 0.5)
        #expect(abs(animator.locals[0].translation.x - expectedX) < 1e-4)
    }

    @Test func aLookAtNodeFacesItsTargetAsTheTargetMoves() throws {
        var animator = try Self.animator(
            [
                Block("NiNode", Self.node(name: 0, children: [1, 2])),
                Block("NiNode", Self.node(name: 1, controller: 3)),
                Block("NiNode", Self.node(name: 2, controller: 5, at: [10, 0, 0])),
                Block(
                    "NiTransformController",
                    NIFBlockFixture.transformController(interpolator: 4)
                ),
                Block("NiLookAtInterpolator", NIFBlockFixture.lookAtInterpolator(lookAt: 2))
            ] + Self.moving(first: 5, from: [10, 0, 0], to: [0, 10, 0]),
            strings: ["Root", "Head", "Target"]
        )
        animator.step(deltaTime: 0)
        #expect(simd_distance(animator.locals[1].rotation.act([1, 0, 0]), [1, 0, 0]) < 1e-4)
        animator.step(deltaTime: 1)
        #expect(simd_distance(animator.locals[1].rotation.act([1, 0, 0]), [0, 1, 0]) < 1e-4)
        #expect(simd_distance(animator.locals[1].rotation.act([0, 0, 1]), [0, 0, 1]) < 1e-4)
    }

    @Test func aLagBoneTrailsItsParentThenSettles() throws {
        var animator = try Self.animator(
            [
                Block("NiNode", Self.node(name: 0, controller: 2, children: [1])),
                Block("NiNode", Self.node(name: 1, controller: 1 + 4, at: [0, 0, 10]))
            ] + Self.moving(first: 2, from: .zero, to: [100, 0, 0]) + [
                Block("BSLagBoneController", NIFBlockFixture.lagBoneController(
                    linearVelocity: 4, linearRotation: 4, maximumDistance: 30
                ))
            ],
            strings: ["Parent", "Tail"]
        )
        for _ in 0 ..< 5 {
            animator.step(deltaTime: 0.1)
        }
        let parent = animator.modelTransform(of: 0).translation
        let tail = animator.modelTransform(of: 1).translation
        #expect(tail.x < parent.x - 1)
        #expect(simd_distance(tail, parent + [0, 0, 10]) <= 30 + 1e-3)
        for _ in 0 ..< 60 {
            animator.step(deltaTime: 0.1)
        }
        let settled = animator.modelTransform(of: 1).translation
        #expect(simd_distance(settled, [100, 0, 10]) < 0.01)
    }

    @Test func aBoneBeyondItsLODDistanceStopsAnimating() throws {
        let blocks = [
            Block("NiNode", Self.node(name: 0, extraData: [5], children: [1])),
            Block("NiNode", Self.node(name: 1, controller: 2))
        ] + Self.moving(first: 2, from: .zero, to: [10, 0, 0]) + [
            Block("BSBoneLODExtraData", NIFBlockFixture.boneLODExtraData([(500, 1)]))
        ]
        var near = try Self.animator(blocks, strings: ["Root", "Tail"])
        near.step(deltaTime: 0.5, cameraDistance: 400)
        #expect(abs(near.locals[1].translation.x - 5) < 1e-4)
        var far = try Self.animator(blocks, strings: ["Root", "Tail"])
        far.step(deltaTime: 0.5, cameraDistance: 600)
        #expect(far.locals[1].translation.x == 0)
        #expect(far.frozen == [1])
    }

    @Test func theBoneLODControllerListsEachLevelsNodes() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            Block("NiNode", Self.node(name: 0, controller: 2, children: [1])),
            Block("NiNode", Self.node(name: 1)),
            Block("NiBSBoneLODController", NIFBlockFixture.boneLODController(levels: [[0, 1], [1]]))
        ], strings: ["Root", "Tail"]))
        let lod = try #require(NIFNodeAnimation(file: file).boneLOD)
        #expect(lod.levels == [[0, 1], [1]])
    }

    @Test func aFollowingNodeFacesAlongItsPathAndBanksInTheTurn() throws {
        var animator = try Self.animator([
            Block("NiNode", Self.node(name: 0, controller: 1)),
            Block("NiTransformController", NIFBlockFixture.transformController(
                stop: 2, interpolator: 2
            )),
            Block("NiPathInterpolator", NIFBlockFixture.pathInterpolator(
                flags: 0x20 | 0x8, bank: (1, 0.5), pathData: 3, percentData: 4
            )),
            Block("NiPosData", NIFBlockFixture.keyGroup([
                (0, [0, 0, 0]), (1, [10, 0, 0]), (2, [10, 10, 0])
            ])),
            Block("NiFloatData", NIFBlockFixture.keyGroup([(0, [0]), (2, [1])]))
        ], strings: ["Bird"])
        animator.step(deltaTime: 0.5)
        let straight = animator.locals[0]
        #expect(simd_distance(straight.translation, [5, 0, 0]) < 1e-3)
        #expect(simd_distance(straight.rotation.act([1, 0, 0]), [1, 0, 0]) < 1e-3)
        #expect(simd_distance(straight.rotation.act([0, 0, 1]), [0, 0, 1]) < 1e-3)
        animator.step(deltaTime: 0.5)
        let turning = animator.locals[0].rotation
        #expect(abs(turning.act([0, 0, 1]).z - cos(0.5)) < 0.05)
        animator.step(deltaTime: 0.5)
        #expect(simd_distance(animator.locals[0].rotation.act([1, 0, 0]), [0, 1, 0]) < 1e-3)
    }
}
