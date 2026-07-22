// Pure UI-layer tests (M8.1.1): anchor/padding/stack math, pixel snapping at
// several scales, text measurement + wrap, draw-list vertex generation,
// budget drop accounting, and scene-resolve determinism. No Metal device
// needed (CoreText/CoreGraphics run headless), so these always execute.

import CoreText
@testable import opensky
import simd
import Testing

struct UILayoutTests {
    // MARK: - Anchoring + padding

    @Test
    func centerAnchorCentersChild() {
        let container = UIRect(x: 0, y: 0, width: 200, height: 100)
        let rect = UIAnchor.center.rect(
            ofSize: UISize(width: 100, height: 50), in: container, offset: UIPoint(x: 0, y: 0)
        )
        #expect(rect == UIRect(x: 50, y: 25, width: 100, height: 50))
    }

    @Test
    func cornerAnchorsPinToCorners() {
        let container = UIRect(x: 0, y: 0, width: 100, height: 100)
        let size = UISize(width: 20, height: 20)
        let topRight = UIAnchor.topRight.rect(
            ofSize: size,
            in: container,
            offset: UIPoint(x: -5, y: 5)
        )
        #expect(topRight == UIRect(x: 75, y: 5, width: 20, height: 20))
        let bottomLeft = UIAnchor.bottomLeft.rect(
            ofSize: size, in: container, offset: UIPoint(x: 5, y: -5)
        )
        #expect(bottomLeft == UIRect(x: 5, y: 75, width: 20, height: 20))
    }

    @Test
    func insetShrinksRect() {
        let rect = UIRect(x: 0, y: 0, width: 100, height: 100).inset(by: UIInsets(all: 10))
        #expect(rect == UIRect(x: 10, y: 10, width: 80, height: 80))
    }

    // MARK: - Vertical stack

    @Test
    func verticalStackStacksWithSpacing() {
        let stack = UIVerticalStack(spacing: 4, alignment: .leading)
        let sizes = [UISize(width: 30, height: 10), UISize(width: 30, height: 10)]
        let frames = stack.layout(sizes: sizes, in: UIRect(x: 0, y: 0, width: 100, height: 100))
        #expect(frames[0] == UIRect(x: 0, y: 0, width: 30, height: 10))
        #expect(frames[1] == UIRect(x: 0, y: 14, width: 30, height: 10))
        #expect(stack.totalHeight(sizes: sizes) == 24)
    }

    @Test
    func verticalStackCenterAligns() {
        let stack = UIVerticalStack(spacing: 0, alignment: .center)
        let frames = stack.layout(
            sizes: [UISize(width: 40, height: 10)], in: UIRect(x: 0, y: 0, width: 100, height: 100)
        )
        #expect(frames[0].x == 30)
    }

    // MARK: - Pixel snapping

    @Test(arguments: [Float(1.0), 1.5, 2.0])
    func snapRoundsEdgesToWholePixels(scale rawScale: Float) {
        let scale = UIScale(rawScale)
        let rect = scale.snapRect(UIRect(x: 10.3, y: 20.7, width: 5, height: 5))
        #expect(rect.minX == (10.3 * rawScale).rounded())
        #expect(rect.maxX == ((10.3 + 5) * rawScale).rounded())
        // Width stays a whole number of pixels.
        #expect(rect.width == rect.maxX - rect.minX)
        #expect(rect.width.rounded() == rect.width)
    }

    @Test
    func scaleClampsToRange() {
        #expect(UIScale(0.1).factor == UIScale.range.lowerBound)
        #expect(UIScale(10).factor == UIScale.range.upperBound)
    }

    // MARK: - Text measurement + wrap

    @Test
    func longerStringMeasuresWider() {
        let font = UIFont(pointSize: 14)
        let short = UITextShaper.measure("Hi", font: font)
        let long = UITextShaper.measure("Hi there, longer line", font: font)
        #expect(long.width > short.width)
        #expect(long.height == short.height)
    }

    @Test
    func wrapProducesMultipleLinesAtNarrowWidth() {
        let font = UIFont(pointSize: 13)
        let text = "This is a fairly long sentence that will not fit on a single narrow line."
        let lines = UITextShaper.wrap(text, font: font, maxWidth: 60)
        #expect(lines.count > 1)
    }

    @Test
    func wrapKeepsSingleLineWhenWide() {
        let lines = UITextShaper.wrap("short", font: UIFont(pointSize: 13), maxWidth: 1000)
        #expect(lines == ["short"])
    }

    // MARK: - Draw list

    @Test
    func fillRectEmitsOneWhiteTexelQuad() {
        let white = SIMD2<Float>(0.01, 0.02)
        var list = UIDrawList(whiteUV: white)
        let color = SIMD4<Float>(0.2, 0.4, 0.6, 1)
        list.fillRect(UIRect(x: 0, y: 0, width: 10, height: 10), color: color)
        #expect(list.quadCount == 1)
        #expect(list.vertices.count == UIDrawList.verticesPerQuad)
        #expect(list.vertices.allSatisfy { $0.uv == white })
        #expect(list.vertices.allSatisfy { $0.color == color })
    }

    @Test
    func strokeRectEmitsFourEdgeQuads() {
        var list = UIDrawList(whiteUV: .zero)
        list.strokeRect(
            UIRect(x: 0, y: 0, width: 40, height: 40),
            lineWidth: 2,
            color: SIMD4(1, 1, 1, 1)
        )
        #expect(list.quadCount == 4)
    }

    @Test
    func glyphQuadCarriesCellUV() {
        var list = UIDrawList(whiteUV: .zero)
        let uvMin = SIMD2<Float>(0.1, 0.2)
        let uvMax = SIMD2<Float>(0.3, 0.5)
        list.addGlyphQuad(
            rect: UIRect(x: 0, y: 0, width: 8, height: 12),
            uvMin: uvMin, uvMax: uvMax, color: SIMD4(1, 1, 1, 1)
        )
        #expect(list.glyphCount == 1)
        // Top-left corner samples uvMin, bottom-right samples uvMax.
        #expect(list.vertices.first?.uv == uvMin)
        #expect(list.vertices.contains { $0.uv == uvMax })
    }

    // MARK: - Budget drop accounting

    @Test
    func budgetDropsOverflowQuadsExactly() {
        var list = UIDrawList(whiteUV: .zero)
        for index in 0 ..< 10 {
            list.fillRect(
                UIRect(x: Float(index), y: 0, width: 1, height: 1), color: SIMD4(1, 1, 1, 1)
            )
        }
        let budgeted = list.budgeted(maxQuads: 4)
        #expect(budgeted.quads == 4)
        #expect(budgeted.dropped == 6)
        #expect(budgeted.vertices.count == 4 * UIDrawList.verticesPerQuad)
    }

    @Test
    func budgetKeepsAllWhenUnderCap() {
        var list = UIDrawList(whiteUV: .zero)
        list.fillRect(UIRect(x: 0, y: 0, width: 1, height: 1), color: SIMD4(1, 1, 1, 1))
        let budgeted = list.budgeted(maxQuads: 4096)
        #expect(budgeted.quads == 1)
        #expect(budgeted.dropped == 0)
    }

    // MARK: - Scene resolve determinism

    @Test
    func resolveIsDeterministic() {
        let atlas = UIGlyphAtlas()
        let viewport = SIMD2<Float>(480, 320)
        let first = UIScene.labSample.resolve(viewportPixels: viewport, scale: 1, atlas: atlas)
        let second = UIScene.labSample.resolve(viewportPixels: viewport, scale: 1, atlas: atlas)
        #expect(first.quadCount == second.quadCount)
        #expect(first.glyphCount == second.glyphCount)
        #expect(vertexBytes(first.vertices) == vertexBytes(second.vertices))
    }

    @Test
    func labSampleResolvesToDrawsWithText() {
        let atlas = UIGlyphAtlas()
        let list = UIScene.labSample.resolve(
            viewportPixels: SIMD2(480, 320), scale: 1, atlas: atlas
        )
        // Panel + border edges + markers + heading/body/paragraph glyphs.
        #expect(list.quadCount > 20)
        #expect(list.glyphCount > 10)
    }

    @Test
    func emptySceneResolvesToNothing() {
        let list = UIScene.empty.resolve(
            viewportPixels: SIMD2(480, 320), scale: 1, atlas: UIGlyphAtlas()
        )
        #expect(list.quadCount == 0)
        #expect(list.vertices.isEmpty)
    }

    private func vertexBytes(_ vertices: [UIVertex]) -> [UInt8] {
        vertices.withUnsafeBytes { Array($0) }
    }
}
