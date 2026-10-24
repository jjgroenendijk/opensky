// `InteriorFogOverride`: a script's fog applies to the lighting it was made from, and a
// near plane past the far one swaps the two.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyRenderCore
import Testing

struct InteriorFogOverrideTests {
    private static func lighting(fog: FogParameters?) -> RenderLighting {
        RenderLighting(
            ambientColor: SIMD3(0.1, 0.1, 0.1), directionalAmbient: .black,
            directionalDirection: SIMD3(0, 0, -1), directionalColor: .zero, fog: fog
        )
    }

    @Test func changesApplyOnlyToTheirOwnLighting() {
        let recorded = FogParameters(
            nearColor: .zero, farColor: .zero, nearDistance: 10, farDistance: 500,
            power: 1, maximum: 1
        )
        let base = Self.lighting(fog: recorded)
        var override = InteriorFogOverride(base: base)
        override.setColours(near: SIMD3(1, 0, 0), far: SIMD3(0, 0, 1))
        override.setPlanes(near: 2000, far: 100)
        override.setPower(3)
        let fog = override.fog(for: base)
        #expect(fog?.nearColor == SIMD3(1, 0, 0))
        #expect(fog?.farColor == SIMD3(0, 0, 1))
        #expect(fog?.nearDistance == 100)
        #expect(fog?.farDistance == 2000)
        #expect(fog?.power == 3)
        #expect(override.fog(for: Self.lighting(fog: nil)) == nil)
    }

    @Test func aCellWithoutFogNeedsPlanesFirst() {
        let base = Self.lighting(fog: nil)
        var override = InteriorFogOverride(base: base)
        override.setColours(near: SIMD3(1, 1, 1), far: SIMD3(1, 1, 1))
        #expect(override.fog(for: base) == nil)
        override.setPlanes(near: 0, far: 1000)
        #expect(override.fog(for: base)?.farDistance == 1000)
    }
}
