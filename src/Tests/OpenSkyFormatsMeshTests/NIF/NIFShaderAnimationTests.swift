// Shader property controllers that play on their own clock become a material track.
// Variable names per NifTools nif.xml; docs/formats/nif-controllers.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFShaderAnimationTests {
    @Test func aFreeLightingUOffsetControllerScrollsTheMaterial() throws {
        let file = try NIFFile(data: Self.file(flags: 0x08))
        let material = try #require(file.model().materials.first)
        let animation = try #require(material.animation)
        #expect(animation.tracks.map(\.target) == [.uOffset])
        #expect(material.animated(by: animation, at: 1).uvOffset.x == 0.5)
        #expect(material.animated(by: animation, at: 3).uvOffset.x == 0.5, "the loop wraps at 2 s")

        let entry = try #require(NIFShaderAnimation.controllers(in: file).first)
        #expect(entry.variableName == "U Offset")
        #expect(entry.keyCount == 2)
    }

    @Test func aSequenceFedOrInactiveControllerDoesNotPlay() throws {
        for flags: UInt16 in [0x28, 0x00] {
            let file = try NIFFile(data: Self.file(flags: flags))
            #expect(try file.model().materials.first?.animation == nil)
            #expect(try NIFShaderAnimation.controllers(in: file).count == 1)
        }
    }

    /// Blocks: 0 shape, 1 lit shader, 2 controller, 3 and 4 the float keys.
    private static func file(flags: UInt16) -> Data {
        var controller = Data()
        controller.appendUInt32(0xFFFF_FFFF)
        controller.appendUInt16(flags)
        for value in [Float(1), 0, 0, 2] {
            controller.appendFloat32(value)
        }
        controller.appendUInt32(1)
        controller.appendUInt32(3)
        controller.appendUInt32(20)
        var float = Data()
        float.appendFloat32(NIFFloat.invalid)
        float.appendUInt32(4)
        var floatData = Data()
        floatData.appendUInt32(2)
        floatData.appendUInt32(1)
        for (time, value) in [(Float(0), Float(0)), (2, 1)] {
            floatData.appendFloat32(time)
            floatData.appendFloat32(value)
        }
        return NIFFixture.file(blocks: [
            .init("BSTriShape", NIFFixture.staticTriangleShape(shaderPropertyRef: 1)),
            .init(
                "BSLightingShaderProperty",
                NIFFixture.bsLightingShaderProperty(controllerRef: 2)
            ),
            .init("BSLightingShaderPropertyFloatController", controller),
            .init("NiFloatInterpolator", float),
            .init("NiFloatData", floatData)
        ])
    }
}
