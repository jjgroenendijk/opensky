import Foundation
public import OpenSkyMenusInterface
public import OpenSkyRenderCore
import simd

nonisolated extension MessageBoxPresentation {
    private static let width: Float = 520
    private static let rowHeight: Float = 26
    private static let textHeight: Float = 150

    private static let text = SIMD4<Float>(0.92, 0.94, 1, 1)
    private static let dim = SIMD4<Float>(0.60, 0.62, 0.68, 1)
    private static let highlight = SIMD4<Float>(0.95, 0.90, 0.75, 1)

    private var height: Float {
        Self.textHeight + Float(request.buttons.count) * Self.rowHeight + 90
    }

    private func label(_ string: String, y: Float, size: Float, color: SIMD4<Float>) -> UINode {
        MenuTextPanel.label(string, y: y, size: size, color: color, panelWidth: Self.width)
    }

    public var scene: UIScene {
        var nodes = [UINode(
            anchor: .center,
            content: .panel(
                size: UISize(width: Self.width, height: height),
                color: SIMD4(0.05, 0.05, 0.07, 0.92),
                border: UIBorder(width: 2, color: SIMD4(0.55, 0.50, 0.40, 1))
            )
        )]
        let top = -height / 2
        if let title = request.title, !title.isEmpty {
            nodes.append(label(title, y: top + 24, size: 16, color: Self.highlight))
        }
        nodes.append(label(
            request.text,
            y: top + 50 + Self.textHeight / 2,
            size: 13,
            color: Self.text
        ))
        let firstRow = top + 60 + Self.textHeight
        for (row, button) in request.buttons.enumerated() {
            let chosen = row == selection
            let marker = chosen ? "> \(button.text) <" : button.text
            nodes.append(label(
                marker, y: firstRow + Float(row) * Self.rowHeight, size: 14,
                color: chosen ? Self.highlight : Self.dim
            ))
        }
        nodes.append(label(Self.hint, y: height / 2 - 16, size: 10, color: Self.dim))
        return UIScene(nodes: nodes)
    }
}
