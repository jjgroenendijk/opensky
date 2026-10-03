// The open message box as a 2D `UIScene`: a title, the text, and one row per
// button with the highlighted row marked. OpenSky's own layout; the vanilla
// box is a Scaleform movie. See docs/engine/messages.md#message-boxes.

import Foundation
import OpenSkyRendering
import simd

nonisolated public struct MessageBoxPresentation: Equatable, Sendable {
    public let request: MessageBoxRequest
    public let selection: Int

    public init(request: MessageBoxRequest, selection: Int) {
        self.request = request
        self.selection = selection
    }

    static let width: Float = 520
    static let rowHeight: Float = 26
    static let textHeight: Float = 150
    public static let hint = "W/S: choose   E or Enter: accept   Esc: close a one-button box"

    private static let text = SIMD4<Float>(0.92, 0.94, 1, 1)
    private static let dim = SIMD4<Float>(0.60, 0.62, 0.68, 1)
    private static let highlight = SIMD4<Float>(0.95, 0.90, 0.75, 1)

    var height: Float {
        Self.textHeight + Float(request.buttons.count) * Self.rowHeight + 90
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

    private func label(_ string: String, y: Float, size: Float, color: SIMD4<Float>) -> UINode {
        UINode(
            anchor: .center,
            offset: UIPoint(x: 0, y: y),
            content: .label(UILabel(
                text: string, font: UIFont(pointSize: size), color: color, maxWidth: Self.width - 40
            ))
        )
    }
}
