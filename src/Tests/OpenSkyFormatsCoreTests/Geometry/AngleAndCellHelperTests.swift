// The degree readout of a wound heading, and the middle of an exterior cell.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct AngleAndCellHelperTests {
    @Test
    func aHeadingPastOneTurnReadsInsideHalfATurn() {
        #expect(abs(MatrixMath.signedDegrees(fromRadians: .pi * 2.5) - 90) < 0.001)
        #expect(abs(MatrixMath.signedDegrees(fromRadians: -.pi * 1.5) - 90) < 0.001)
        #expect(abs(MatrixMath.fullTurn - 2 * .pi) < 0.0001)
    }

    @Test
    func theCellCentreIsHalfACellIn() {
        #expect(CellCoordinate(x: 0, y: 0).centre == SIMD2(2048, 2048))
        #expect(CellCoordinate(x: -1, y: 2).centre == SIMD2(-2048, 2.5 * 4096))
    }
}
