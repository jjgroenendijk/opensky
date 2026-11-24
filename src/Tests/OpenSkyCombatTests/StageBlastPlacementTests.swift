// A destruction stage's explosion: the bounds centre turned with the reference, and a
// random offset that stays within the bound radius.

@testable import OpenSkyCombat
import simd
import Testing

struct StageBlastPlacementTests {
    @Test func noRadiusPutsTheBlastAtTheTurnedCentre() {
        let position = StageBlastPlacement.position(
            origin: SIMD3(100, 0, 0), bounds: (SIMD3(0, 10, 5), 0), heading: .pi / 2,
            random: { 0.5 }
        )
        #expect(simd_distance(position, SIMD3(110, 0, 5)) < 1e-4)
    }

    @Test func theOffsetStaysWithinTheRadius() {
        var draws: [Float] = [0.25, 1, 0.999]
        let position = StageBlastPlacement.position(
            origin: .zero, bounds: (.zero, 40), heading: 0,
            random: { draws.isEmpty ? 0 : draws.removeFirst() }
        )
        #expect(simd_length(position) <= 40)
        #expect(position.z > 39)
    }
}
