// The IMGS DNAM depth of field values through the image-space parameters.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyRenderCore
import Testing

struct ImageSpaceDepthOfFieldTests {
    private typealias Fixture = ESMFixture

    static func imageSpace(strength: Float, distance: Float, range: Float) throws -> ImageSpace {
        try ImageSpace(record: Fixture.record("IMGS", fields: [
            ("EDID", Fixture.zstring("Focus")),
            ("DNAM", Fixture.f32(strength, distance, range))
        ]))
    }

    @Test func theImageSpaceCarriesItsFocus() throws {
        let parameters = try ImageSpaceParameters(
            Self.imageSpace(strength: 0.5, distance: 1000, range: 2000)
        )
        #expect(parameters.depthOfField == SIMD3(0.5, 1000, 2000))
        #expect(parameters.isNeutral)
    }

    @Test func blendingWeighsTheFocus() throws {
        let near = try ImageSpaceParameters(Self.imageSpace(strength: 1, distance: 0, range: 0))
        let far = try ImageSpaceParameters(
            Self.imageSpace(strength: 0, distance: 4000, range: 400)
        )
        let blended = ImageSpaceParameters.blend([(near, 0.25), (far, 0.75)])
        #expect(blended.depthOfField == SIMD3(0.25, 3000, 300))
    }

    @Test func displayClampKeepsTheStrengthAShare() throws {
        var parameters = ImageSpaceParameters()
        parameters.depthOfField = SIMD3(3, -10, 500)
        #expect(parameters.clampedForDisplay.depthOfField == SIMD3(1, 0, 500))
    }
}
