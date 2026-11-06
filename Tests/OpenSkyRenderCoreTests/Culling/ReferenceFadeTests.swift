// Distance fades of placed references by category and size.

@testable import OpenSkyRenderCore
import Testing

struct ReferenceFadeTests {
    let fades = ReferenceFadeDistances(actors: 10, items: 5, objects: 15)
    let lower = SIMD3<Float>(-64, -64, -64)
    let upper = SIMD3<Float>(64, 64, 64)

    @Test
    func bandFollowsTheBoundRadius() throws {
        let band = try #require(fades.band(.object, radius: 100))
        // End 1000, start 600: fade from 720, gone at 880, times 15.
        #expect(abs(band.lowerBound - 15 * 720) < 0.01)
        #expect(abs(band.upperBound - 15 * 880) < 0.01)
        #expect(fades.band(.none, radius: 100) == nil)
    }

    @Test
    func smallReferenceKeepsTheMinimumStart() throws {
        let band = try #require(fades.band(.item, radius: 10))
        // Start 500, end 1000: fade from 650, gone at 850, times 5.
        #expect(abs(band.lowerBound - 5 * 650) < 0.01)
        #expect(abs(band.upperBound - 5 * 850) < 0.01)
    }

    @Test
    func hugeReferenceStopsAtTheLoadedGrid() throws {
        let band = try #require(fades.band(.object, radius: 4096))
        let end = ReferenceFadeDistances.gridReach - 4096
        let start = 0.6 * end
        #expect(abs(band.upperBound - 15 * (start + 0.7 * (end - start))) < 0.1)
    }

    @Test
    func nearReferenceIsWholeAndFarOneIsGone() throws {
        let radius = Float(3).squareRoot() * 64
        let band = try #require(fades.band(.actor, radius: radius))
        #expect(fades.fade(.actor, lower: lower, upper: upper, viewer: .zero) == 0)
        let far = SIMD3<Float>(band.upperBound + 1, 0, 0)
        #expect(fades.fade(.actor, lower: lower, upper: upper, viewer: far) == nil)
        let middle = SIMD3<Float>((band.lowerBound + band.upperBound) / 2, 0, 0)
        let fade = try #require(fades.fade(.actor, lower: lower, upper: upper, viewer: middle))
        #expect(abs(fade - 0.5) < 0.01)
    }

    @Test
    func zeroMultiplierNeverFades() {
        let viewer = SIMD3<Float>(1e6, 0, 0)
        #expect(ReferenceFadeDistances.off.isOn == false)
        #expect(ReferenceFadeDistances.off.fade(
            .object,
            lower: lower,
            upper: upper,
            viewer: viewer
        ) == 0)
    }
}
