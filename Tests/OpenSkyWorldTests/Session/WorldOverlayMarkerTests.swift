// The overlay marker the lock and trap sections draw on their selection.

@testable import OpenSkyDiagnostics
import OpenSkyShaderTypes
import Testing

struct WorldOverlayMarkerTests {
    @Test func aMarkerIsThreeCrossedLines() {
        var list = WorldOverlayDrawList()
        list.addMarker(at: SIMD3(1, 2, 3), size: 4, color: SIMD4(1, 1, 0, 1))
        let budget = list.budgeted(maxPrimitives: 10)
        #expect(budget.lineSegmentCount == 3)
        #expect(budget.vertices.first?.position.x == -3)
    }
}
