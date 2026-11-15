// The Vampire Lord cape's cloth: the top vertices pinned to the shape, an edge per triangle
// side, and capsule collision, all in world space (docs/engine/cape-cloth.md). Pure.

public import simd

/// A capsule the cloth stays out of, in world space.
nonisolated public struct ClothCapsule: Equatable, Sendable {
    public var start: SIMD3<Float>
    public var end: SIMD3<Float>
    public var radius: Float

    public init(start: SIMD3<Float>, end: SIMD3<Float>, radius: Float) {
        self.start = start
        self.end = end
        self.radius = radius
    }

    /// `point` moved out to the surface along the line from the nearest point on the
    /// segment; a point outside stays.
    func pushOut(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let axis = end - start
        let lengthSquared = simd_length_squared(axis)
        let along = lengthSquared > 0
            ? simd_clamp(simd_dot(point - start, axis) / lengthSquared, 0, 1) : 0
        let closest = start + along * axis
        let offset = point - closest
        let distance = simd_length(offset)
        guard distance < radius else { return point }
        guard distance > 0.000001 else { return closest }
        return closest + offset * (radius / distance)
    }
}

nonisolated public struct VerletCloth: Sendable {
    public static let pinCount = 12
    public static let iterations = 50
    /// The step length, the same every frame whatever the frame time.
    public static let stepSeconds: Float = 0.033
    /// Units per second squared, down world z.
    public static let gravity: Float = 1500

    struct Edge: Sendable {
        let first: Int
        let second: Int
        let rest: Float
    }

    /// Each vertex in the shape's own space, as the mesh stores it.
    public let rest: [SIMD3<Float>]
    /// The vertices with the highest local z, which follow the shape.
    public let pins: [Int]
    let edges: [Edge]
    /// Each vertex in world space now.
    public private(set) var positions: [SIMD3<Float>]
    private var previous: [SIMD3<Float>]
    private var lastStep = stepSeconds
    private let pinned: Set<Int>

    /// Nil for a mesh with no triangle or an index past its vertices.
    public init?(rest: [SIMD3<Float>], triangles: [UInt16], shapeToWorld: float4x4) {
        guard
            !rest.isEmpty, triangles.count >= 3,
            triangles.allSatisfy({ Int($0) < rest.count })
        else { return nil }
        self.rest = rest
        let highestFirst = rest.indices.sorted { left, right in
            rest[left].z == rest[right].z ? left < right : rest[left].z > rest[right].z
        }
        pins = Array(highestFirst.prefix(Self.pinCount))
        pinned = Set(pins)
        let world = rest.map { Self.apply(shapeToWorld, to: $0) }
        var edges: [Edge] = []
        for corner in stride(from: 0, to: triangles.count - 2, by: 3) {
            let indices = (0 ..< 3).map { Int(triangles[corner + $0]) }
            for side in 0 ..< 3 {
                let first = indices[side]
                let second = indices[(side + 1) % 3]
                edges.append(Edge(
                    first: first, second: second, rest: simd_distance(world[first], world[second])
                ))
            }
        }
        self.edges = edges
        positions = world
        previous = world
    }

    /// One step. `seconds` at or below zero is a paused frame, which is skipped.
    public mutating func step(seconds: Float, shapeToWorld: float4x4, capsules: [ClothCapsule]) {
        guard seconds > 0 else { return }
        let step = Self.stepSeconds
        let ratio = step / lastStep
        let drop = Self.gravity * step * step
        for index in positions.indices where !pinned.contains(index) {
            let now = positions[index]
            var next = now + (now - previous[index]) * ratio
            next.z -= drop
            previous[index] = now
            positions[index] = next
        }
        let targets = pins.map { Self.apply(shapeToWorld, to: rest[$0]) }
        for _ in 0 ..< Self.iterations {
            for edge in edges {
                let delta = positions[edge.first] - positions[edge.second]
                let length = simd_length(delta)
                guard length > 0 else { continue }
                let correction = delta * (0.5 * (length - edge.rest) / length)
                positions[edge.first] -= correction
                positions[edge.second] += correction
            }
            for capsule in capsules {
                for index in positions.indices {
                    positions[index] = capsule.pushOut(positions[index])
                }
            }
            for (pin, target) in zip(pins, targets) {
                positions[pin] = target
            }
        }
        for pin in pins {
            previous[pin] = positions[pin]
        }
        lastStep = step
    }

    /// Each vertex back in the shape's own space; a pin gets its rest position exactly.
    public func localPositions(shapeToWorld: float4x4) -> [SIMD3<Float>] {
        let worldToShape = shapeToWorld.inverse
        var local = positions.map { Self.apply(worldToShape, to: $0) }
        for pin in pins {
            local[pin] = rest[pin]
        }
        return local
    }

    static func apply(_ matrix: float4x4, to point: SIMD3<Float>) -> SIMD3<Float> {
        let moved = matrix * SIMD4(point, 1)
        return SIMD3(moved.x, moved.y, moved.z)
    }
}
