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

    private func step(
        _ state: ReferenceFadeState?, at distance: Float, seconds: Float
    ) -> ReferenceFadeState? {
        fades.step(
            .actor,
            bounds: ReferenceFadeBounds(lower: lower, upper: upper, viewer: SIMD3(distance, 0, 0)),
            state: state, seconds: seconds
        )
    }

    private var actorBand: ClosedRange<Float> {
        get throws {
            try #require(fades.band(.actor, radius: Float(3).squareRoot() * 64))
        }
    }

    @Test
    func aFirstSightTakesItsSideAtOnce() throws {
        let band = try actorBand
        #expect(step(nil, at: 0, seconds: 0)?.dissolve == 0)
        #expect(step(nil, at: band.upperBound + 1, seconds: 0)?.isGone == true)
    }

    @Test
    func passingTheBandFadesOutOverTwoSeconds() throws {
        let band = try actorBand
        var state = step(nil, at: 0, seconds: 0)
        state = step(state, at: band.upperBound + 1, seconds: 1)
        #expect(state?.dissolve == 0.5)
        state = step(state, at: band.upperBound + 1, seconds: 1)
        #expect(state?.isGone == true)
    }

    @Test
    func insideTheBandTheDirectionHolds() throws {
        let band = try actorBand
        let middle = (band.lowerBound + band.upperBound) / 2
        var state = step(nil, at: band.upperBound + 1, seconds: 0)
        state = step(state, at: middle, seconds: 1)
        #expect(state?.isGone == true)
        state = step(state, at: band.lowerBound - 1, seconds: 0.6)
        #expect(abs((state?.dissolve ?? 0) - 0.5) < 0.001)
        state = step(state, at: middle, seconds: 0.6)
        #expect(state?.dissolve == 0)
    }

    @Test
    func zeroMultiplierNeverFades() {
        #expect(ReferenceFadeDistances.off.isOn == false)
        let bounds = ReferenceFadeBounds(lower: lower, upper: upper, viewer: SIMD3(1e6, 0, 0))
        #expect(ReferenceFadeDistances.off.step(
            .object, bounds: bounds, state: nil, seconds: 1
        ) == nil)
    }
}
