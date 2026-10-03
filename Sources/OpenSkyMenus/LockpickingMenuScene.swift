// The lockpicking overlay as a 2D `UIScene`: the pick's arc as dots, the pick,
// the keyhole turning with the lock, and health and pick counts. OpenSky's
// own layout; vanilla draws a 3D lock. See docs/engine/locks.md.

import Foundation
import OpenSkyInventoryInterface
import OpenSkyRendering
import simd

nonisolated extension LockpickingMenuPresentation {
    static let panelSize = UISize(width: 420, height: 340)
    static let arcRadius: Float = 120
    static let arcStep: Float = 10
    static let pickDots = 12
    static let keyholeDots = 5
    static let barWidth: Float = 240
    public static let hint = "Mouse or A/D: move pick   W: turn lock   Esc: leave"

    private static let dim = SIMD4<Float>(0.45, 0.48, 0.55, 1)
    private static let bright = SIMD4<Float>(0.95, 0.90, 0.75, 1)
    private static let strain = SIMD4<Float>(0.95, 0.40, 0.30, 1)
    private static let text = SIMD4<Float>(0.92, 0.94, 1, 1)

    public var scene: UIScene {
        var nodes = [UINode(
            anchor: .center,
            content: .panel(
                size: Self.panelSize,
                color: SIMD4(0.05, 0.05, 0.07, 0.88),
                border: UIBorder(width: 2, color: SIMD4(0.55, 0.50, 0.40, 1))
            )
        )]
        nodes += arcNodes + pickNodes + keyholeNodes + barNodes + labelNodes
        return UIScene(nodes: nodes)
    }

    /// The pick's travel: dots every `arcStep` degrees across `halfArc` either side.
    private var arcNodes: [UINode] {
        let steps = Int((halfArc / Self.arcStep).rounded(.down))
        return (-steps ... max(-steps, steps)).map { step in
            dot(angle: Float(step) * Self.arcStep, radius: Self.arcRadius, size: 4, color: Self.dim)
        }
    }

    private var pickNodes: [UINode] {
        let color = isStraining ? Self.strain : Self.bright
        return (1 ... Self.pickDots).map { index in
            let radius = Self.arcRadius * Float(index) / Float(Self.pickDots)
            return dot(angle: pickAngle, radius: radius, size: 5, color: color)
        }
    }

    /// The keyhole slot turns a quarter turn as the lock opens.
    private var keyholeNodes: [UINode] {
        (0 ..< Self.keyholeDots).map { index in
            let radius = Float(index - Self.keyholeDots / 2) * 6
            return dot(angle: lockRotation * 90, radius: radius, size: 6, color: Self.text)
        }
    }

    private var barNodes: [UINode] {
        bar(fraction: lockRotation, y: 40, color: Self.bright)
            + bar(fraction: pickHealth, y: 60, color: isStraining ? Self.strain : Self.dim)
    }

    private var labelNodes: [UINode] {
        [
            label("\(title) (\(difficulty.name))", y: -150, size: 16),
            label("Lockpicks: \(picksRemaining)", y: 84, size: 13),
            label(Self.hint, y: 140, size: 11)
        ]
    }

    private func dot(angle: Float, radius: Float, size: Float, color: SIMD4<Float>) -> UINode {
        let radians = angle * .pi / 180
        return UINode(
            anchor: .center,
            offset: UIPoint(x: radius * sin(radians), y: -radius * cos(radians)),
            content: .marker(size: UISize(width: size, height: size), color: color)
        )
    }

    private func bar(fraction: Float, y: Float, color: SIMD4<Float>) -> [UINode] {
        let filled = Self.barWidth * min(max(fraction, 0), 1)
        let track = UINode(
            anchor: .center,
            offset: UIPoint(x: 0, y: y),
            content: .marker(size: UISize(width: Self.barWidth, height: 6), color: Self.dim * 0.5)
        )
        guard filled > 0 else { return [track] }
        let fill = UINode(
            anchor: .center,
            offset: UIPoint(x: (filled - Self.barWidth) / 2, y: y),
            content: .marker(size: UISize(width: filled, height: 6), color: color)
        )
        return [track, fill]
    }

    private func label(_ string: String, y: Float, size: Float) -> UINode {
        let font = UIFont(pointSize: size)
        let width = Self.panelSize.width - 32
        return UINode(
            anchor: .center,
            offset: UIPoint(x: 0, y: y),
            content: .label(UILabel(text: string, font: font, color: Self.text, maxWidth: width))
        )
    }
}
