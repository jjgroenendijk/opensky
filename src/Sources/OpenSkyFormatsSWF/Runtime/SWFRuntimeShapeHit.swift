// Shape-level hits, as Flash routes the mouse and as `hitTest(x, y, true)` tests: a
// shape on its fill and stroke triangles, a clip through any visible child. Text and
// buttons keep their box.

import Foundation
import simd

nonisolated extension SWFMovieRuntime {
    /// True when the node draws at a point in its own local twips.
    func draws(
        _ node: SWFDisplayObject,
        at localPoint: SIMD2<Float>,
        remainingDepth: Int = SWFDisplayObject.maximumTreeDepth
    ) -> Bool {
        switch node.content {
        case let .shape(id):
            guard let shape = movie.shape(id), SWFBoundsBox(rect: shape.bounds).contains(localPoint)
            else {
                return false
            }
            return hitMeshes.mesh(for: shape).contains(localPoint)
        case .staticText, .editText:
            return containsLocally(node, localPoint: localPoint)
        case .clip:
            if node.isButton {
                return containsLocally(node, localPoint: localPoint)
            }
            guard remainingDepth > 0 else {
                return false
            }
            return node.children.contains { child in
                guard
                    child.isVisible, child.clipDepth == nil,
                    let inverse = SWFTransform(matrix: child.matrix).inverted
                else {
                    return false
                }
                return draws(
                    child,
                    at: inverse.apply(localPoint),
                    remainingDepth: remainingDepth - 1
                )
            }
        }
    }
}

nonisolated extension SWFShapeMesh {
    /// True when a point lies in any triangle, edges included.
    func contains(_ point: SIMD2<Float>) -> Bool {
        stride(from: 0, to: vertices.count - 2, by: 3).contains { index in
            let first = vertices[index], second = vertices[index + 1], third = vertices[index + 2]
            guard cross(second - first, third - first) != 0 else {
                return false
            }
            let sides = [
                cross(second - first, point - first),
                cross(third - second, point - second),
                cross(first - third, point - third)
            ]
            return sides.allSatisfy { $0 >= 0 } || sides.allSatisfy { $0 <= 0 }
        }
    }

    private func cross(_ edge: SIMD2<Float>, _ offset: SIMD2<Float>) -> Float {
        edge.x * offset.y - edge.y * offset.x
    }
}
