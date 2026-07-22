// Screen-space UI geometry value types (M8.1.1). Pure deterministic float
// math, unit-testable without Metal. Layout works in resolution-independent
// UI points; UIScale converts points -> framebuffer pixels with deterministic
// edge snapping so rects and glyph origins land on whole pixels.

import simd

/// A point in UI point space (origin top-left, y down).
struct UIPoint: Equatable {
    var x: Float
    var y: Float
}

/// A size in UI point space. Non-negative by convention; callers clamp.
struct UISize: Equatable {
    var width: Float
    var height: Float
}

/// An axis-aligned rect (origin top-left, y down).
struct UIRect: Equatable {
    var x: Float
    var y: Float
    var width: Float
    var height: Float

    var minX: Float {
        x
    }

    var minY: Float {
        y
    }

    var maxX: Float {
        x + width
    }

    var maxY: Float {
        y + height
    }

    /// Shrinks the rect by `insets`; degenerate results clamp to zero extent.
    func inset(by insets: UIInsets) -> UIRect {
        UIRect(
            x: x + insets.left,
            y: y + insets.top,
            width: max(width - insets.left - insets.right, 0),
            height: max(height - insets.top - insets.bottom, 0)
        )
    }
}

/// Edge padding in UI points.
struct UIInsets: Equatable {
    var top: Float
    var left: Float
    var bottom: Float
    var right: Float

    static let zero = UIInsets(top: 0, left: 0, bottom: 0, right: 0)

    init(top: Float, left: Float, bottom: Float, right: Float) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    init(all value: Float) {
        self.init(top: value, left: value, bottom: value, right: value)
    }
}

/// Nine-point anchoring: the named point of a child aligns to the same-named
/// point of its container, plus an offset.
enum UIAnchor: CaseIterable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight

    /// Horizontal unit position: 0 left, 0.5 center, 1 right.
    var unitX: Float {
        switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .top, .center, .bottom: 0.5
        case .topRight, .right, .bottomRight: 1
        }
    }

    /// Vertical unit position: 0 top, 0.5 center, 1 bottom.
    var unitY: Float {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .left, .center, .right: 0.5
        case .bottomLeft, .bottom, .bottomRight: 1
        }
    }

    /// Positions a child of `size` inside `container`: the child's anchor point
    /// lands on the container's anchor point, shifted by `offset`.
    func rect(ofSize size: UISize, in container: UIRect, offset: UIPoint) -> UIRect {
        let anchorX = container.x + container.width * unitX
        let anchorY = container.y + container.height * unitY
        return UIRect(
            x: anchorX - size.width * unitX + offset.x,
            y: anchorY - size.height * unitY + offset.y,
            width: size.width,
            height: size.height
        )
    }
}

/// UI points -> framebuffer pixels. Clamped to `range`; edges snap to whole
/// pixels independently (min + max each rounded) so 1px strokes stay crisp and
/// widths stay stable regardless of sub-pixel origin.
struct UIScale: Equatable {
    static let range: ClosedRange<Float> = 0.5 ... 4

    let factor: Float

    init(_ raw: Float) {
        factor = min(max(raw, Self.range.lowerBound), Self.range.upperBound)
    }

    /// Points -> pixels, no snapping.
    func pixels(_ points: Float) -> Float {
        points * factor
    }

    /// Points -> nearest whole pixel.
    func snap(_ points: Float) -> Float {
        (points * factor).rounded()
    }

    /// Converts a point rect to a pixel rect, snapping each edge independently.
    func snapRect(_ rect: UIRect) -> UIRect {
        let minX = snap(rect.minX)
        let minY = snap(rect.minY)
        let maxX = snap(rect.maxX)
        let maxY = snap(rect.maxY)
        return UIRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
