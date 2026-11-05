// How several modifiers combine (CK wiki "ImageSpace Modifiers") and the radial blur ramps.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyRenderCore
import Testing

struct ImageSpaceModifierRulesTests {
    static func sample(
        _ values: [ImageSpaceChannel: Float] = [:],
        tint: SIMD4<Float>? = nil,
        center: SIMD2<Float>? = nil
    ) -> ImageSpaceAdapterSample {
        ImageSpaceAdapterSample(
            time: 0, values: values, tint: tint, fade: nil, radialBlurCenter: center,
            isFinished: false
        )
    }

    @Test func theBlurRadiusIsTheHighestNotTheSum() {
        let result = ImageSpaceParameters.neutral
            .applying(Self.sample([.blurRadius: 4]), strength: 1)
            .applying(Self.sample([.blurRadius: 3]), strength: 1)
            .applying(Self.sample([.blurRadius: 6]), strength: 0.5)
        #expect(result.blurRadius == 4)
    }

    @Test func theTintIsAnAlphaWeightedAverageWithTheHighestAlpha() {
        let tint = ImageSpaceParameters.averageTint([
            SIMD4(1, 0, 0, 0.75), SIMD4(0, 0, 1, 0.25)
        ])
        #expect(tint == SIMD4(0.75, 0, 0.25, 0.75))
        #expect(ImageSpaceParameters.averageTint([SIMD4(1, 1, 1, 0)]) == SIMD4(1, 1, 1, 0))
    }

    @Test func theTintDoesNotDependOnTheModifierOrder() {
        let red = Self.sample(tint: SIMD4(1, 0, 0, 0.5))
        let blue = Self.sample(tint: SIMD4(0, 0, 1, 0.5))
        let first = ImageSpaceParameters.averageTint([.zero, red.tint ?? .zero, blue.tint ?? .zero])
        let second = ImageSpaceParameters.averageTint([
            .zero,
            blue.tint ?? .zero,
            red.tint ?? .zero
        ])
        #expect(first == second)
        #expect(first == SIMD4(0.5, 0, 0.5, 0.5))
    }

    @Test func theStrongestRadialBlurKeepsItsWholeShape() {
        let weak = Self.sample(
            [.radialBlurStrength: 2, .radialBlurStart: 0.1, .radialBlurRampUp: 1]
        )
        let strong = Self.sample(
            [.radialBlurStrength: 5, .radialBlurStart: 0.4, .radialBlurRampUp: 10],
            center: SIMD2(0.3, 0.6)
        )
        let result = ImageSpaceParameters.neutral
            .applying(strong, strength: 1)
            .applying(weak, strength: 1)
        #expect(result.radialBlur.strength == 5)
        #expect(result.radialBlur.start == 0.4)
        #expect(result.radialBlur.center == SIMD2(0.3, 0.6))
        #expect(!result.isNeutral)
    }

    @Test func theRadialRampsRiseFromStartAndFallAfterDownStart() {
        var blur = ImageSpaceRadialBlur()
        blur.strength = 1
        blur.start = 0.2
        blur.rampUp = 5
        #expect(blur.weight(atRadius: 0.1) == 0)
        #expect(abs(blur.weight(atRadius: 0.3) - 0.5) < 1e-5)
        #expect(blur.weight(atRadius: 0.9) == 1)
        blur.downStart = 0.6
        blur.rampDown = 2
        #expect(abs(blur.weight(atRadius: 0.85) - 0.5) < 1e-5)
        #expect(blur.weight(atRadius: 1.2) == 0)
    }

    @Test func motionBlurKeepsTheHighestAndClampsForDisplay() {
        var result = ImageSpaceParameters.neutral
            .applying(Self.sample([.motionBlurStrength: 0.35]), strength: 1)
            .applying(Self.sample([.motionBlurStrength: 0.15]), strength: 1)
        #expect(result.motionBlur == 0.35)
        result.motionBlur = 3
        result.radialBlur.strength = .nan
        #expect(result.clampedForDisplay.motionBlur == 1)
        #expect(result.clampedForDisplay.radialBlur.strength == 0)
    }
}
