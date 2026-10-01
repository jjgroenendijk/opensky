// Pure world-space debug-overlay input, budgeting and source registry.
// Subsystems append colored triangles and line segments each frame; the
// renderer performs one bounded upload from the resulting flat vertex list.

import OpenSkyShaderTypes
import simd

nonisolated public struct WorldOverlayPoint: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let color: SIMD4<Float>
}

nonisolated public struct WorldOverlayTriangle: Equatable, Sendable {
    public let first: WorldOverlayPoint
    public let second: WorldOverlayPoint
    public let third: WorldOverlayPoint
}

nonisolated public struct WorldOverlayLineSegment: Equatable, Sendable {
    public let first: WorldOverlayPoint
    public let second: WorldOverlayPoint
}

nonisolated public enum WorldOverlayPrimitive: Equatable, Sendable {
    case triangle(WorldOverlayTriangle)
    case lineSegment(WorldOverlayLineSegment)
}

/// GPU-ready result after applying the hard primitive budget. Triangle
/// vertices precede line vertices so one buffer supports one draw per topology.
nonisolated public struct WorldOverlayBudgetResult: Sendable {
    public let vertices: [OverlayVertex]
    public let submittedPrimitiveCount: Int
    public let triangleCount: Int
    public let lineSegmentCount: Int
    public let droppedPrimitiveCount: Int

    public var drawnPrimitiveCount: Int {
        triangleCount + lineSegmentCount
    }

    public var triangleVertexCount: Int {
        triangleCount * 3
    }

    public var lineVertexCount: Int {
        lineSegmentCount * 2
    }
}

nonisolated public struct WorldOverlayDrawList: Sendable {
    public private(set) var primitives: [WorldOverlayPrimitive] = []

    public var primitiveCount: Int {
        primitives.count
    }

    public mutating func addTriangle(
        _ first: WorldOverlayPoint,
        _ second: WorldOverlayPoint,
        _ third: WorldOverlayPoint
    ) {
        primitives.append(.triangle(WorldOverlayTriangle(
            first: first,
            second: second,
            third: third
        )))
    }

    public mutating func addTriangle(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        color: SIMD4<Float>
    ) {
        addTriangle(
            WorldOverlayPoint(position: first, color: color),
            WorldOverlayPoint(position: second, color: color),
            WorldOverlayPoint(position: third, color: color)
        )
    }

    public mutating func addLineSegment(
        _ first: WorldOverlayPoint,
        _ second: WorldOverlayPoint
    ) {
        primitives.append(.lineSegment(WorldOverlayLineSegment(
            first: first,
            second: second
        )))
    }

    public mutating func addLineSegment(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        color: SIMD4<Float>
    ) {
        addLineSegment(
            WorldOverlayPoint(position: first, color: color),
            WorldOverlayPoint(position: second, color: color)
        )
    }

    public mutating func addPolyline(_ points: [SIMD3<Float>], color: SIMD4<Float>) {
        guard points.count > 1 else { return }
        for index in 1 ..< points.count {
            addLineSegment(points[index - 1], points[index], color: color)
        }
    }

    /// Keeps the first `maxPrimitives` in submission order, then groups their
    /// vertices by topology for the two GPU draws. Negative caps keep none.
    public func budgeted(maxPrimitives: Int) -> WorldOverlayBudgetResult {
        let keptCount = min(max(maxPrimitives, 0), primitives.count)
        var triangleVertices: [OverlayVertex] = []
        var lineVertices: [OverlayVertex] = []
        var triangleCount = 0
        var lineSegmentCount = 0
        for primitive in primitives.prefix(keptCount) {
            switch primitive {
            case let .triangle(triangle):
                triangleVertices.append(Self.vertex(triangle.first))
                triangleVertices.append(Self.vertex(triangle.second))
                triangleVertices.append(Self.vertex(triangle.third))
                triangleCount += 1
            case let .lineSegment(line):
                lineVertices.append(Self.vertex(line.first))
                lineVertices.append(Self.vertex(line.second))
                lineSegmentCount += 1
            }
        }
        return WorldOverlayBudgetResult(
            vertices: triangleVertices + lineVertices,
            submittedPrimitiveCount: primitives.count,
            triangleCount: triangleCount,
            lineSegmentCount: lineSegmentCount,
            droppedPrimitiveCount: primitives.count - keptCount
        )
    }

    private static func vertex(_ point: WorldOverlayPoint) -> OverlayVertex {
        OverlayVertex(position: point.position, color: point.color)
    }
}

/// Renderer-owned switches exposed to a source while it builds one frame.
/// Future sources can ignore these and gate on their own subsystem state.
nonisolated public struct WorldOverlayFrameContext: Equatable, Sendable {
    public let navmeshOverlayEnabled: Bool
    public let pathOverlayEnabled: Bool
    /// Perception view cones and investigate positions.
    public let detectionOverlayEnabled: Bool
    /// The conversation camera's pivot, sightline and eye.
    public let dialogueCameraOverlayEnabled: Bool

    public init(
        navmeshOverlayEnabled: Bool = false,
        pathOverlayEnabled: Bool = false,
        detectionOverlayEnabled: Bool = false,
        dialogueCameraOverlayEnabled: Bool = false
    ) {
        self.navmeshOverlayEnabled = navmeshOverlayEnabled
        self.pathOverlayEnabled = pathOverlayEnabled
        self.detectionOverlayEnabled = detectionOverlayEnabled
        self.dialogueCameraOverlayEnabled = dialogueCameraOverlayEnabled
    }
}

/// Stable-order registry. Re-registering an identifier replaces its closure
/// in place, which lets a subsystem refresh ownership without changing draw
/// order or growing the registry.
public final class WorldOverlaySourceRegistry {
    public typealias Source = (WorldOverlayFrameContext, inout WorldOverlayDrawList) -> Void

    private struct Entry {
        let identifier: String
        var source: Source
    }

    private var entries: [Entry] = []

    public var sourceCount: Int {
        entries.count
    }

    public func register(identifier: String, source: @escaping Source) {
        if let index = entries.firstIndex(where: { $0.identifier == identifier }) {
            entries[index].source = source
        } else {
            entries.append(Entry(identifier: identifier, source: source))
        }
    }

    public func remove(identifier: String) {
        entries.removeAll { $0.identifier == identifier }
    }

    public func makeDrawList(context: WorldOverlayFrameContext) -> WorldOverlayDrawList {
        var list = WorldOverlayDrawList()
        for entry in entries {
            entry.source(context, &list)
        }
        return list
    }

    public init() {}
}
