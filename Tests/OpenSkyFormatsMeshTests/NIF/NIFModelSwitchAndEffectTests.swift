// Scene-graph flatten of selector nodes and effect shapes. Synthetic in-code
// files only (NIFFixture); docs/formats/nif.md.

import FormatsCoreTesting
import FormatsMeshTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFModelSwitchAndEffectTests {
    private func shape(shaderPropertyRef: Int32 = -1, alphaPropertyRef: Int32 = -1) -> Data {
        NIFFixture.staticTriangleShape(
            shaderPropertyRef: shaderPropertyRef,
            alphaPropertyRef: alphaPropertyRef
        )
    }

    @Test func switchNodeDrawsOnlyItsActiveChild() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("NiSwitchNode", NIFFixture.niSwitchNode(children: [2, 3], activeIndex: 1)),
            .init("BSTriShape", shape()),
            .init("NiNode", NIFFixture.niNode(children: [4, 5])),
            .init("BSTriShape", shape()),
            .init("BSTriShape", shape())
        ]))
        #expect(try file.model().meshes.count == 2)
    }

    @Test func switchNodeIndexPastItsChildrenDrawsNothing() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiSwitchNode", NIFFixture.niSwitchNode(children: [1], activeIndex: 4)),
            .init("BSTriShape", shape())
        ]))
        #expect(try file.model().meshes.isEmpty)
    }
}
