// One branch of a NIF as a model: an AMMO model's quiver without the arrow on the
// string. Synthetic in-code files only (NIFFixture).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFSubtreeModelTests {
    /// Root -> ArrowQuiver (moved up 5) -> quiver shape, and root -> the loose arrow.
    private func ammunitionFile() throws -> NIFFile {
        try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("BSFadeNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1, 3]
                )),
                .init("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(
                        nameIndex: 1, translation: SIMD3(0, 0, 5)
                    ),
                    children: [2]
                )),
                .init("BSTriShape", NIFFixture.staticTriangleShape(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 2)
                )),
                .init("BSTriShape", NIFFixture.staticTriangleShape(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 3)
                ))
            ],
            strings: ["Arrow", "ArrowQuiver", "ArrowQuiver:0", "Arrow:0"]
        ))
    }

    @Test func onlyTheShapesBelowTheNamedNodeStayInPlace() throws {
        let file = try ammunitionFile()
        let whole = try file.model()
        let quiver = try file.model(skeleton: nil, keepingRoot: false, below: "arrowquiver")

        #expect(whole.meshes.count == 2)
        #expect(quiver.meshes.map(\.name) == ["ArrowQuiver:0"])
        #expect(quiver.meshes.first?.transform == whole.meshes.first?.transform)
    }

    @Test func anUnknownNodeGivesNoMeshes() throws {
        let model = try ammunitionFile().model(skeleton: nil, keepingRoot: false, below: "Quiver")
        #expect(model.meshes.isEmpty)
    }
}
