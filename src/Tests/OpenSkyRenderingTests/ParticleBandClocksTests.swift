// The particle band clocks: a near system steps every frame, a far one in its band, and
// the skipped time goes into the next step.

@testable import OpenSkyGameData
@testable import OpenSkyRendering
import Testing

struct ParticleBandClocksTests {
    private final class System {}

    /// One second at 60 frames a second. The far system is capped at the reduced band,
    /// so it steps about 15 times, and its steps still add up to nearly the whole second.
    @Test func aFarSystemStepsLessOftenAndKeepsItsTime() {
        let near = System()
        let far = System()
        var clocks = ParticleBandClocks()
        var nearSteps: [Float] = []
        var farSteps: [Float] = []
        for _ in 0 ..< 60 {
            if let step = clocks.step(of: near, at: .zero, viewer: .zero, deltaTime: 1.0 / 60) {
                nearSteps.append(step)
            }
            if let step = clocks.step(
                of: far, at: SIMD3(20000, 0, 0), viewer: .zero, deltaTime: 1.0 / 60
            ) {
                farSteps.append(step)
            }
        }
        #expect(nearSteps.count == 60)
        #expect((13 ... 16).contains(farSteps.count))
        #expect(abs(farSteps.reduce(0, +) - 1) <= ParticleBandClocks.longestStep + 0.001)
        #expect(clocks.bandCounts == [.full: 1, .distant: 1])
        clocks.keep([near])
        #expect(clocks.bandCounts == [.full: 1])
    }
}
