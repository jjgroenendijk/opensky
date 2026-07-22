// Built-in UI sample scenes (M8.1.1). `labSample` is the milestone's
// verification scene: heading + body text, a long wrapped paragraph, a filled
// panel with border, and anchored corner markers exercising the four corners.
// Tests render it offscreen; the later UI Lab sidebar panel displays it.

import simd

extension UIScene {
    static let labSample = UIScene(nodes: [
        // Filled panel + light border, top-left.
        UINode(
            anchor: .topLeft,
            offset: UIPoint(x: 24, y: 24),
            content: .panel(
                size: UISize(width: 320, height: 200),
                color: SIMD4(0.06, 0.07, 0.10, 0.85),
                border: UIBorder(width: 2, color: SIMD4(0.55, 0.62, 0.75, 1))
            )
        ),
        // Heading (bold).
        UINode(
            anchor: .topLeft,
            offset: UIPoint(x: 40, y: 40),
            content: .label(UILabel(
                text: "OpenSky UI",
                font: UIFont(pointSize: 22, weight: .bold),
                color: SIMD4(0.96, 0.97, 1, 1)
            ))
        ),
        // Body line.
        UINode(
            anchor: .topLeft,
            offset: UIPoint(x: 40, y: 74),
            content: .label(UILabel(
                text: "Screen-space 2D layer",
                font: UIFont(pointSize: 14),
                color: SIMD4(0.80, 0.85, 0.95, 1)
            ))
        ),
        // Long wrapped paragraph.
        UINode(
            anchor: .topLeft,
            offset: UIPoint(x: 40, y: 100),
            content: .label(UILabel(
                text: "This overlay renders after the finished 3D frame using a "
                    + "shelf-packed glyph atlas and a single premultiplied draw call.",
                font: UIFont(pointSize: 13),
                color: SIMD4(0.72, 0.78, 0.90, 1),
                maxWidth: 288
            ))
        ),
        // Anchored corner markers (offsets point inward so they stay on-screen).
        UINode(
            anchor: .topLeft,
            offset: UIPoint(x: 8, y: 8),
            content: .marker(size: UISize(width: 12, height: 12), color: SIMD4(0.95, 0.45, 0.35, 1))
        ),
        UINode(
            anchor: .topRight,
            offset: UIPoint(x: -8, y: 8),
            content: .marker(size: UISize(width: 12, height: 12), color: SIMD4(0.45, 0.85, 0.55, 1))
        ),
        UINode(
            anchor: .bottomLeft,
            offset: UIPoint(x: 8, y: -8),
            content: .marker(size: UISize(width: 12, height: 12), color: SIMD4(0.40, 0.65, 0.95, 1))
        ),
        UINode(
            anchor: .bottomRight,
            offset: UIPoint(x: -8, y: -8),
            content: .marker(size: UISize(width: 12, height: 12), color: SIMD4(0.95, 0.85, 0.40, 1))
        )
    ])
}
