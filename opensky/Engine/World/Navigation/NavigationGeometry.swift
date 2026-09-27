// Projection and two-dimensional geometry helpers for navmesh queries.

import simd

nonisolated enum NavigationGeometry {
    static let epsilon: Float = 0.0001

    static func cross(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Float {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    /// Closest XY point with Z reconstructed from barycentric weights on the
    /// triangle plane. Degenerate triangles are filtered by the caller.
    static func closestPoint(
        on triangle: RuntimeNavigationTriangle,
        to point: SIMD3<Float>
    ) -> SIMD3<Float> {
        let first = SIMD2(triangle.vertices.first.x, triangle.vertices.first.y)
        let second = SIMD2(triangle.vertices.second.x, triangle.vertices.second.y)
        let third = SIMD2(triangle.vertices.third.x, triangle.vertices.third.y)
        let triangle2D = NavigationTriangle2D(first: first, second: second, third: third)
        let projected = closestPoint(
            on: triangle2D,
            to: SIMD2(point.x, point.y)
        )
        let weights = barycentric(projected, in: triangle2D)
        let height = weights.x * triangle.vertices.first.z
            + weights.y * triangle.vertices.second.z
            + weights.z * triangle.vertices.third.z
        return SIMD3(projected.x, projected.y, height)
    }

    /// Ericson's region tests, applied in XY so feet project vertically onto
    /// slopes while still clamping to triangle borders.
    private static func closestPoint(
        on triangle: NavigationTriangle2D,
        to point: SIMD2<Float>
    ) -> SIMD2<Float> {
        let first = triangle.first
        let second = triangle.second
        let third = triangle.third
        let firstSecond = second - first
        let firstThird = third - first
        let firstPoint = point - first
        let firstDot = simd_dot(firstSecond, firstPoint)
        let secondDot = simd_dot(firstThird, firstPoint)
        if firstDot <= 0, secondDot <= 0 {
            return first
        }

        let secondPoint = point - second
        let thirdDot = simd_dot(firstSecond, secondPoint)
        let fourthDot = simd_dot(firstThird, secondPoint)
        if thirdDot >= 0, fourthDot <= thirdDot {
            return second
        }

        let firstEdge = firstDot * fourthDot - thirdDot * secondDot
        if firstEdge <= 0, firstDot >= 0, thirdDot <= 0 {
            return first + (firstDot / (firstDot - thirdDot)) * firstSecond
        }

        let thirdPoint = point - third
        let fifthDot = simd_dot(firstSecond, thirdPoint)
        let sixthDot = simd_dot(firstThird, thirdPoint)
        if sixthDot >= 0, fifthDot <= sixthDot {
            return third
        }

        let secondEdge = fifthDot * secondDot - firstDot * sixthDot
        if secondEdge <= 0, secondDot >= 0, sixthDot <= 0 {
            return first + (secondDot / (secondDot - sixthDot)) * firstThird
        }

        let thirdEdge = thirdDot * sixthDot - fifthDot * fourthDot
        if thirdEdge <= 0, fourthDot - thirdDot >= 0, fifthDot - sixthDot >= 0 {
            let ratio = (fourthDot - thirdDot)
                / ((fourthDot - thirdDot) + (fifthDot - sixthDot))
            return second + ratio * (third - second)
        }

        let denominator = 1 / (firstEdge + secondEdge + thirdEdge)
        let secondWeight = secondEdge * denominator
        let thirdWeight = firstEdge * denominator
        return first + firstSecond * secondWeight + firstThird * thirdWeight
    }

    private static func barycentric(
        _ point: SIMD2<Float>,
        in triangle: NavigationTriangle2D
    ) -> SIMD3<Float> {
        let first = triangle.first
        let second = triangle.second
        let third = triangle.third
        let denominator = cross(second - first, third - first)
        let secondWeight = cross(point - first, third - first) / denominator
        let thirdWeight = cross(second - first, point - first) / denominator
        return SIMD3(1 - secondWeight - thirdWeight, secondWeight, thirdWeight)
    }
}

nonisolated private struct NavigationTriangle2D {
    let first: SIMD2<Float>
    let second: SIMD2<Float>
    let third: SIMD2<Float>
}
