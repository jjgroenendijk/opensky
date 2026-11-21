// A glyph quad laid out upright turns and slants with the text's transform, and the field's
// bottom edge cuts it in the upright space.

import OpenSkyFormatsSWF
@testable import OpenSkyRendering
import OpenSkyShaderTypes
import simd
import Testing

struct SWFTextQuadTests {
    private func close(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
        simd_distance(lhs, rhs) < 1e-4
    }

    @Test func uprightTransformKeepsTheQuadAxisAligned() throws {
        let shape = SWFTextQuad.shape(of: SWFTransform(scaleX: 2, scaleY: 2, translateX: 5))
        let quad = try #require(SWFTextQuad(
            origin: SIMD2(10, 20), shape: shape,
            localMin: SIMD2(1, -8), localMax: SIMD2(5, 2),
            localBottom: nil, uvMin: .zero, uvMax: .one
        ))
        #expect(close(quad.topLeft, SIMD2(11, 12)))
        #expect(close(quad.bottomRight, SIMD2(15, 22)))
    }

    @Test func quarterTurnRotatesEveryCornerAboutThePen() throws {
        // Clockwise on screen: x goes down, y goes left.
        let turn = SWFTransform(
            scaleX: 0, rotateSkew0: 3, rotateSkew1: -3, scaleY: 0, translateX: 0, translateY: 0
        )
        let shape = SWFTextQuad.shape(of: turn)
        let quad = try #require(SWFTextQuad(
            origin: SIMD2(100, 100), shape: shape,
            localMin: SIMD2(0, -10), localMax: SIMD2(4, 0),
            localBottom: nil, uvMin: .zero, uvMax: .one
        ))
        #expect(close(quad.topLeft, SIMD2(110, 100)))
        #expect(close(quad.topRight, SIMD2(110, 104)))
        #expect(close(quad.bottomLeft, SIMD2(100, 100)))
        #expect(close(quad.bottomRight, SIMD2(100, 104)))
    }

    @Test func skewSlantsTheQuadSides() throws {
        let skew = SWFTransform(
            scaleX: 1, rotateSkew0: 0, rotateSkew1: 0.5, scaleY: 1, translateX: 0, translateY: 0
        )
        let quad = try #require(SWFTextQuad(
            origin: .zero, shape: SWFTextQuad.shape(of: skew),
            localMin: SIMD2(0, -10), localMax: SIMD2(4, 0),
            localBottom: nil, uvMin: .zero, uvMax: .one
        ))
        #expect(close(quad.topLeft, SIMD2(-5, -10)))
        #expect(close(quad.bottomLeft, SIMD2(0, 0)))
        #expect(close(quad.topRight, SIMD2(-1, -10)))
    }

    @Test func bottomEdgeCutsTheQuadAndItsTexture() throws {
        let quad = try #require(SWFTextQuad(
            origin: .zero, shape: .identity,
            localMin: SIMD2(0, -10), localMax: SIMD2(4, 10),
            localBottom: 0, uvMin: SIMD2(0, 0.2), uvMax: SIMD2(1, 0.6)
        ))
        #expect(close(quad.bottomLeft, SIMD2(0, 0)))
        #expect(abs(quad.uvMax.y - 0.4) < 1e-5)
        #expect(SWFTextQuad(
            origin: .zero, shape: .identity,
            localMin: SIMD2(0, -10), localMax: SIMD2(4, 10),
            localBottom: -10, uvMin: .zero, uvMax: .one
        ) == nil)
    }

    @Test func pictureMapsItsPixelsBackToItsUnitSquare() throws {
        let turn = SWFTransform(
            scaleX: 0, rotateSkew0: 1, rotateSkew1: -1, scaleY: 0, translateX: 0, translateY: 0
        )
        let shape = SWFTextQuad.shape(of: turn)
        let toUnit = try #require(SWFTextQuad.pixelsToUnit(
            origin: SIMD2(50, 50), shape: shape, localMin: .zero, localSize: SIMD2(8, 4)
        ))
        let quad = try #require(SWFTextQuad(
            origin: SIMD2(50, 50), shape: shape, localMin: .zero, localMax: SIMD2(8, 4),
            localBottom: nil, uvMin: .zero, uvMax: .one
        ))
        #expect(close(toUnit.apply(quad.topLeft), SIMD2(0, 0)))
        #expect(close(toUnit.apply(quad.bottomRight), SIMD2(1, 1)))
        #expect(close(quad.vertices[4].position, quad.bottomRight))
        #expect(SWFTextQuad.pixelsToUnit(
            origin: .zero, shape: shape, localMin: .zero, localSize: .zero
        ) == nil)
        #expect(SWFTextQuad.shape(of: SWFTransform(scaleX: 0, scaleY: 0)) == .identity)
    }
}
