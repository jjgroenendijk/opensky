// Axis-aligned bounds in twips for the runtime display list. `_width`,
// `_height`, and `hitTest` all need the box a node covers in its parent's
// space, which the immutable scene path never had to compute.
//
// Flash reports `_width`/`_height` as the axis-aligned extent of the
// transformed bounding box, not as the untransformed box scaled — a rotated
// clip is wider than its own artwork. That is what `transformed(by:)` does
// here, by mapping the four corners.

import Foundation
import simd

/// An axis-aligned box in twips. `nil` bounds are represented by `isEmpty`
/// rather than an optional so unions stay cheap.
nonisolated struct SWFBoundsBox: Equatable {
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float
    /// True when nothing has been unioned in yet.
    var isEmpty: Bool

    static let empty = SWFBoundsBox(minX: 0, minY: 0, maxX: 0, maxY: 0, isEmpty: true)

    init(minX: Float, minY: Float, maxX: Float, maxY: Float, isEmpty: Bool = false) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.isEmpty = isEmpty
    }

    init(rect: SWFRect) {
        self.init(
            minX: Float(rect.xMin), minY: Float(rect.yMin),
            maxX: Float(rect.xMax), maxY: Float(rect.yMax)
        )
    }

    var width: Float {
        isEmpty ? 0 : maxX - minX
    }

    var height: Float {
        isEmpty ? 0 : maxY - minY
    }

    mutating func formUnion(_ other: SWFBoundsBox) {
        guard !other.isEmpty else {
            return
        }
        guard !isEmpty else {
            self = other
            return
        }
        minX = min(minX, other.minX)
        minY = min(minY, other.minY)
        maxX = max(maxX, other.maxX)
        maxY = max(maxY, other.maxY)
    }

    /// The axis-aligned box covering this box's four transformed corners.
    func transformed(by transform: SWFTransform) -> SWFBoundsBox {
        guard !isEmpty else {
            return self
        }
        let corners = [
            transform.apply(SIMD2(minX, minY)),
            transform.apply(SIMD2(maxX, minY)),
            transform.apply(SIMD2(minX, maxY)),
            transform.apply(SIMD2(maxX, maxY))
        ]
        var box = SWFBoundsBox(
            minX: corners[0].x, minY: corners[0].y, maxX: corners[0].x, maxY: corners[0].y
        )
        for corner in corners.dropFirst() {
            box.minX = min(box.minX, corner.x)
            box.minY = min(box.minY, corner.y)
            box.maxX = max(box.maxX, corner.x)
            box.maxY = max(box.maxY, corner.y)
        }
        return box
    }

    func contains(_ point: SIMD2<Float>) -> Bool {
        guard !isEmpty else {
            return false
        }
        return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

nonisolated extension SWFMovieRuntime {
    /// The node's own bounds in its local twip space, before its matrix.
    /// A clip unions its children's transformed bounds.
    func localBounds(
        of node: SWFDisplayObject,
        remainingDepth: Int = SWFDisplayObject.maximumTreeDepth
    ) -> SWFBoundsBox {
        switch node.content {
        case let .shape(id):
            return movie.shape(id).map { SWFBoundsBox(rect: $0.bounds) } ?? .empty
        case let .editText(id):
            return movie.editText(id).map { SWFBoundsBox(rect: $0.bounds) } ?? .empty
        case let .staticText(id):
            guard let text = movie.staticText(id) else {
                return .empty
            }
            return SWFBoundsBox(rect: text.bounds)
        case .clip:
            guard remainingDepth > 0 else {
                return .empty
            }
            var box = SWFBoundsBox.empty
            for child in node.children where child.isVisible {
                let inner = localBounds(of: child, remainingDepth: remainingDepth - 1)
                box.formUnion(inner.transformed(by: SWFTransform(matrix: child.matrix)))
            }
            return box
        }
    }

    /// The node's bounds in its parent's space — the box `_width`/`_height`
    /// report.
    func parentBounds(of node: SWFDisplayObject) -> SWFBoundsBox {
        localBounds(of: node).transformed(by: SWFTransform(matrix: node.matrix))
    }
}
