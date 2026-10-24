// The root transform rule: a placed model leaves its root's own transform out,
// and a bone attachment keeps it. docs/formats/nif.md "Scene graph -> engine mesh".

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFRootPlacementTests {
    /// A placed reference's transform replaces the root's own, as the end cap
    /// `NorHallSm1wayEndCap01.nif` needs to meet its corridor. An attachment keeps it.
    @Test func dropsTheRootTransformUnlessKept() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSFadeNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(
                    translation: SIMD3(0, 0, 50),
                    rotationRows: [-1, 0, 0, 0, -1, 0, 0, 0, 1]
                ),
                children: [1]
            )),
            .init("BSTriShape", NIFFixture.staticTriangleShape(
                prefix: NIFFixture.avObjectPrefix(translation: SIMD3(0, 10, 0))
            ))
        ]))
        let placed = try file.model().meshes[0].transform
        let shapeOnly = MatrixMath.translation(SIMD3(0, 10, 0))
        let rootTransform = MatrixMath.translation(SIMD3(0, 0, 50))
            * MatrixMath.rotationZ(radians: .pi)
        let attached = try file.model(keepingRoot: true).meshes[0].transform
        for column in 0 ..< 4 {
            #expect(simd_length(placed[column] - shapeOnly[column]) < 1e-5)
            #expect(
                simd_length(attached[column] - (rootTransform * shapeOnly)[column]) < 1e-5
            )
        }
    }
}
