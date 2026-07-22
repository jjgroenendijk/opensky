// Value-type UI scene (M8.1.1). Nodes anchor point-space content to the
// viewport; `resolve` turns the scene into a pixel-space draw list given the
// framebuffer size + scale, rasterizing needed glyphs into the atlas. Pure
// aside from atlas mutation -> two resolves of one scene are byte-identical.

import CoreText
import simd

/// A border stroke on a panel.
struct UIBorder: Equatable {
    var width: Float
    var color: SIMD4<Float>
}

/// A (optionally wrapped) run of text.
struct UILabel: Equatable {
    var text: String
    var font: UIFont
    var color: SIMD4<Float>
    /// Wrap width in points; nil -> single line.
    var maxWidth: Float?

    init(text: String, font: UIFont, color: SIMD4<Float>, maxWidth: Float? = nil) {
        self.text = text
        self.font = font
        self.color = color
        self.maxWidth = maxWidth
    }
}

/// A node's drawable content.
enum UINodeContent: Equatable {
    case panel(size: UISize, color: SIMD4<Float>, border: UIBorder?)
    case marker(size: UISize, color: SIMD4<Float>)
    case label(UILabel)
}

/// One anchored node: content positioned by anchor + point offset.
struct UINode: Equatable {
    var anchor: UIAnchor
    var offset: UIPoint
    var content: UINodeContent

    init(anchor: UIAnchor, offset: UIPoint = UIPoint(x: 0, y: 0), content: UINodeContent) {
        self.anchor = anchor
        self.offset = offset
        self.content = content
    }
}

struct UIScene {
    var nodes: [UINode]

    init(nodes: [UINode] = []) {
        self.nodes = nodes
    }

    static let empty = UIScene()

    var isEmpty: Bool {
        nodes.isEmpty
    }

    /// Shared per-resolve inputs, bundled to keep helper signatures small.
    private struct ResolveContext {
        let viewportPoints: UIRect
        let scale: UIScale
        let atlas: UIGlyphAtlas
    }

    /// Per-label pixel-space text setup, reused across its wrapped lines.
    private struct LineContext {
        let fontKey: Int
        let pixelFont: CTFont
        let pixelSize: Int
        let originX: Float
        let color: SIMD4<Float>
    }

    /// Resolves the scene to a pixel-space draw list. `atlas` gains any glyphs
    /// the labels need (revision bumps -> renderer re-uploads).
    func resolve(viewportPixels: SIMD2<Float>, scale: Float, atlas: UIGlyphAtlas) -> UIDrawList {
        let scale = UIScale(scale)
        var list = UIDrawList(whiteUV: atlas.whiteUV)
        guard viewportPixels.x > 0, viewportPixels.y > 0 else { return list }
        let context = ResolveContext(
            viewportPoints: UIRect(
                x: 0, y: 0,
                width: viewportPixels.x / scale.factor,
                height: viewportPixels.y / scale.factor
            ),
            scale: scale,
            atlas: atlas
        )
        for node in nodes {
            resolve(node: node, context: context, into: &list)
        }
        return list
    }

    private func resolve(node: UINode, context: ResolveContext, into list: inout UIDrawList) {
        switch node.content {
        case let .panel(size, color, border):
            let rect = context.scale.snapRect(
                node.anchor.rect(ofSize: size, in: context.viewportPoints, offset: node.offset)
            )
            list.fillRect(rect, color: color)
            if let border {
                let lineWidth = max((border.width * context.scale.factor).rounded(), 1)
                list.strokeRect(rect, lineWidth: lineWidth, color: border.color)
            }
        case let .marker(size, color):
            let rect = context.scale.snapRect(
                node.anchor.rect(ofSize: size, in: context.viewportPoints, offset: node.offset)
            )
            list.fillRect(rect, color: color)
        case let .label(label):
            emit(label: label, node: node, context: context, into: &list)
        }
    }

    private func emit(
        label: UILabel,
        node: UINode,
        context: ResolveContext,
        into list: inout UIDrawList
    ) {
        let lines = label.maxWidth
            .map { UITextShaper.wrap(label.text, font: label.font, maxWidth: $0) }
            ?? [label.text]
        guard !lines.isEmpty else { return }
        let pointFont = label.font.makeCTFont(size: CGFloat(label.font.pointSize))
        let lineHeightPoints = UITextShaper.lineMetrics(pointFont).lineHeight
        let blockWidth = lines.map { UITextShaper.shape($0, font: pointFont).width }.max() ?? 0
        let block = node.anchor.rect(
            ofSize: UISize(width: blockWidth, height: lineHeightPoints * Float(lines.count)),
            in: context.viewportPoints,
            offset: node.offset
        )
        let pixelSize = max(Int((label.font.pointSize * context.scale.factor).rounded()), 1)
        let pixelFont = label.font.makeCTFont(size: CGFloat(pixelSize))
        let pixelMetrics = UITextShaper.lineMetrics(pixelFont)
        let lineHeightPixels = pixelMetrics.lineHeight.rounded()
        let ascentPixels = pixelMetrics.ascent.rounded()
        let originY = (block.y * context.scale.factor).rounded()
        let lineContext = LineContext(
            fontKey: label.font.fontKey,
            pixelFont: pixelFont,
            pixelSize: pixelSize,
            originX: (block.x * context.scale.factor).rounded(),
            color: label.color
        )
        for (index, text) in lines.enumerated() {
            emit(
                line: text,
                baseline: originY + ascentPixels + Float(index) * lineHeightPixels,
                context: lineContext,
                atlas: context.atlas,
                into: &list
            )
        }
    }

    private func emit(
        line: String,
        baseline: Float,
        context: LineContext,
        atlas: UIGlyphAtlas,
        into list: inout UIDrawList
    ) {
        let shaped = UITextShaper.shape(line, font: context.pixelFont)
        for glyph in shaped.glyphs {
            let entry = atlas.entry(
                fontKey: context.fontKey,
                glyphID: glyph.glyphID,
                pixelSize: context.pixelSize,
                ctFont: context.pixelFont
            )
            guard !entry.isEmpty else { continue }
            let rect = UIRect(
                x: (context.originX + glyph.x + entry.bearing.x).rounded(),
                y: (baseline - entry.bearing.y).rounded(),
                width: entry.size.x,
                height: entry.size.y
            )
            list.addGlyphQuad(
                rect: rect,
                uvMin: entry.uvMin,
                uvMax: entry.uvMax,
                color: context.color
            )
        }
    }
}
