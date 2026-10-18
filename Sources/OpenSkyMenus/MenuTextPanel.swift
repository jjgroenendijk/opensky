// A plain text panel: what a menu draws while its movie is missing or still loading.
// OpenSky's own layout, so a menu stays usable without the install's interface files.

import Foundation
import OpenSkyRendering
import simd

nonisolated public struct MenuTextPanel: Equatable, Sendable {
    public var title: String
    public var lines: [String]
    /// The line drawn highlighted, if any.
    public var selection: Int?
    public var hint: String

    public init(title: String, lines: [String], selection: Int? = nil, hint: String) {
        self.title = title
        self.lines = lines
        self.selection = selection
        self.hint = hint
    }

    static let width: Float = 560
    static let rowHeight: Float = 22
    static let shownLines = 16
    private static let text = SIMD4<Float>(0.92, 0.94, 1, 1)
    private static let dim = SIMD4<Float>(0.60, 0.62, 0.68, 1)
    private static let highlight = SIMD4<Float>(0.95, 0.90, 0.75, 1)

    /// The lines around the selection, so a long list keeps it in view.
    var visibleRange: Range<Int> {
        let centred = (selection ?? 0) - Self.shownLines / 2
        let start = max(0, min(centred, lines.count - Self.shownLines))
        return start ..< min(lines.count, start + Self.shownLines)
    }

    public var scene: UIScene {
        let rows = visibleRange
        let height = Float(rows.count) * Self.rowHeight + 100
        var nodes = [UINode(
            anchor: .center,
            content: .panel(
                size: UISize(width: Self.width, height: height),
                color: SIMD4(0.05, 0.05, 0.07, 0.92),
                border: UIBorder(width: 2, color: SIMD4(0.55, 0.50, 0.40, 1))
            )
        )]
        let top = -height / 2
        nodes.append(label(title, y: top + 24, size: 16, color: Self.highlight))
        for (offset, row) in rows.enumerated() {
            let chosen = row == selection
            nodes.append(label(
                chosen ? "> \(lines[row]) <" : lines[row],
                y: top + 56 + Float(offset) * Self.rowHeight,
                size: 13,
                color: chosen ? Self.highlight : Self.text
            ))
        }
        nodes.append(label(hint, y: height / 2 - 16, size: 10, color: Self.dim))
        return UIScene(nodes: nodes)
    }

    private func label(_ string: String, y: Float, size: Float, color: SIMD4<Float>) -> UINode {
        Self.label(string, y: y, size: size, color: color, panelWidth: Self.width)
    }

    /// One centred line inside a panel `panelWidth` wide.
    static func label(
        _ string: String, y: Float, size: Float, color: SIMD4<Float>, panelWidth: Float
    ) -> UINode {
        UINode(
            anchor: .center,
            offset: UIPoint(x: 0, y: y),
            content: .label(UILabel(
                text: string, font: UIFont(pointSize: size), color: color, maxWidth: panelWidth - 40
            ))
        )
    }
}
