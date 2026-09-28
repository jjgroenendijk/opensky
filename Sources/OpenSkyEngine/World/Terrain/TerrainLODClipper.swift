// Exact cell ownership for distant terrain. Partially visible BTR blocks are
// clipped triangle-by-triangle against visible cell rectangles; interpolated
// edge vertices preserve every available static-mesh attribute.

import Foundation
import simd

nonisolated struct TerrainLODClipMask: Equatable, Hashable {
    let level: Int32
    private let visibleCellIndexes: Set<Int>

    init(
        level: Int32,
        blockOrigin: CellCoordinate,
        visibleCells: Set<CellCoordinate>
    ) {
        self.level = level
        visibleCellIndexes = Set(visibleCells.compactMap { cell in
            let x = cell.x - blockOrigin.x
            let y = cell.y - blockOrigin.y
            guard x >= 0, x < level, y >= 0, y < level else { return nil }
            return Int(y * level + x)
        })
    }

    var visibleCellCount: Int {
        visibleCellIndexes.count
    }

    var isComplete: Bool {
        visibleCellCount == Int(level * level)
    }

    func contains(localX: Int, localY: Int) -> Bool {
        guard localX >= 0, localX < level, localY >= 0, localY < level else {
            return false
        }
        return visibleCellIndexes.contains(localY * Int(level) + localX)
    }

    func contains(_ cell: CellCoordinate, blockOrigin: CellCoordinate) -> Bool {
        contains(
            localX: Int(cell.x - blockOrigin.x),
            localY: Int(cell.y - blockOrigin.y)
        )
    }

    /// Stable bitset token for clipped GPU-cache variants.
    var cacheKey: String {
        let digits = Array("0123456789abcdef")
        let cellCount = Int(level * level)
        var encoded = String()
        encoded.reserveCapacity((cellCount + 3) / 4)
        for start in stride(from: 0, to: cellCount, by: 4) {
            var nibble = 0
            for bit in 0 ..< min(4, cellCount - start) {
                guard visibleCellIndexes.contains(start + bit) else { continue }
                nibble |= 1 << bit
            }
            encoded.append(digits[nibble])
        }
        return "\(level)-\(encoded)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(level)
        for index in visibleCellIndexes.sorted() {
            hasher.combine(index)
        }
    }
}

nonisolated enum TerrainLODClipper {
    static func clipped(_ model: Model, to mask: TerrainLODClipMask) -> Model {
        guard !mask.isComplete else { return model }
        return Model(
            meshes: model.meshes.flatMap { clipped($0, to: mask) },
            materials: model.materials,
            skippedShapeCount: model.skippedShapeCount
        )
    }

    private struct Vertex {
        let position: SIMD3<Float>
        let modelPosition: SIMD3<Float>
        let normal: SIMD3<Float>?
        let tangent: SIMD3<Float>?
        let bitangent: SIMD3<Float>?
        let uv: SIMD2<Float>?
        let color: SIMD4<Float>?

        func interpolated(to other: Vertex, amount: Float) -> Vertex {
            Vertex(
                position: simd_mix(position, other.position, SIMD3(repeating: amount)),
                modelPosition: simd_mix(
                    modelPosition,
                    other.modelPosition,
                    SIMD3(repeating: amount)
                ),
                normal: Self.direction(normal, other.normal, amount: amount),
                tangent: Self.direction(tangent, other.tangent, amount: amount),
                bitangent: Self.direction(bitangent, other.bitangent, amount: amount),
                uv: Self.value(uv, other.uv, amount: amount),
                color: Self.value(color, other.color, amount: amount)
            )
        }

        private static func direction(
            _ lhs: SIMD3<Float>?,
            _ rhs: SIMD3<Float>?,
            amount: Float
        ) -> SIMD3<Float>? {
            guard let lhs, let rhs else { return nil }
            let value = simd_mix(lhs, rhs, SIMD3(repeating: amount))
            return simd_length_squared(value) > 0 ? simd_normalize(value) : value
        }

        private static func value(
            _ lhs: SIMD2<Float>?,
            _ rhs: SIMD2<Float>?,
            amount: Float
        ) -> SIMD2<Float>? {
            guard let lhs, let rhs else { return nil }
            return simd_mix(lhs, rhs, SIMD2(repeating: amount))
        }

        private static func value(
            _ lhs: SIMD4<Float>?,
            _ rhs: SIMD4<Float>?,
            amount: Float
        ) -> SIMD4<Float>? {
            guard let lhs, let rhs else { return nil }
            return simd_mix(lhs, rhs, SIMD4(repeating: amount))
        }
    }

    private struct Accumulator {
        let source: Mesh
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var bitangents: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt16] = []

        var hasRoom: Bool {
            positions.count <= Int(UInt16.max) - 2
        }

        mutating func append(_ triangle: [Vertex]) {
            guard triangle.count == 3 else { return }
            for vertex in triangle {
                indices.append(UInt16(positions.count))
                positions.append(vertex.position)
                if let normal = vertex.normal {
                    normals.append(normal)
                }
                if let tangent = vertex.tangent {
                    tangents.append(tangent)
                }
                if let bitangent = vertex.bitangent {
                    bitangents.append(bitangent)
                }
                if let uv = vertex.uv {
                    uvs.append(uv)
                }
                if let color = vertex.color {
                    colors.append(color)
                }
            }
        }

        func mesh(chunk: Int) -> Mesh? {
            guard !indices.isEmpty else { return nil }
            let baseName = source.name ?? "terrain-lod"
            return Mesh(
                name: "\(baseName)-clip-\(chunk)",
                transform: source.transform,
                positions: positions,
                normals: normals,
                tangents: tangents,
                bitangents: bitangents,
                uvs: uvs,
                colors: colors,
                indices: indices,
                materialSlot: source.materialSlot
            )
        }
    }

    private static func clipped(_ mesh: Mesh, to mask: TerrainLODClipMask) -> [Mesh] {
        var output: [Mesh] = []
        var accumulator = Accumulator(source: mesh)
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let triangle = (0 ..< 3).map { vertexIndex in
                vertex(mesh, at: Int(mesh.indices[offset + vertexIndex]))
            }
            for piece in pieces(of: triangle, visibleIn: mask) {
                guard hasArea(piece) else { continue }
                if !accumulator.hasRoom {
                    if let chunk = accumulator.mesh(chunk: output.count) {
                        output.append(chunk)
                    }
                    accumulator = Accumulator(source: mesh)
                }
                accumulator.append(piece)
            }
        }
        if let chunk = accumulator.mesh(chunk: output.count) {
            output.append(chunk)
        }
        return output
    }

    private static func vertex(_ mesh: Mesh, at index: Int) -> Vertex {
        let position = mesh.positions[index]
        let moved = mesh.transform * SIMD4(position, 1)
        return Vertex(
            position: position,
            modelPosition: SIMD3(moved.x, moved.y, moved.z),
            normal: mesh.normals.isEmpty ? nil : mesh.normals[index],
            tangent: mesh.tangents.isEmpty ? nil : mesh.tangents[index],
            bitangent: mesh.bitangents.isEmpty ? nil : mesh.bitangents[index],
            uv: mesh.uvs.isEmpty ? nil : mesh.uvs[index],
            color: mesh.colors.isEmpty ? nil : mesh.colors[index]
        )
    }

    private static func pieces(
        of triangle: [Vertex],
        visibleIn mask: TerrainLODClipMask
    ) -> [[Vertex]] {
        let cellSize = TerrainMeshBuilder.cellSize
        let minX = triangle.map(\.modelPosition.x).min() ?? 0
        let maxX = triangle.map(\.modelPosition.x).max() ?? 0
        let minY = triangle.map(\.modelPosition.y).min() ?? 0
        let maxY = triangle.map(\.modelPosition.y).max() ?? 0
        let lowerX = max(0, Int(floor(minX / cellSize)))
        let upperX = min(Int(mask.level) - 1, Int(floor((maxX - 0.001) / cellSize)))
        let lowerY = max(0, Int(floor(minY / cellSize)))
        let upperY = min(Int(mask.level) - 1, Int(floor((maxY - 0.001) / cellSize)))
        guard lowerX <= upperX, lowerY <= upperY else { return [] }

        var output: [[Vertex]] = []
        for y in lowerY ... upperY {
            for x in lowerX ... upperX where mask.contains(localX: x, localY: y) {
                let west = Float(x) * cellSize
                let east = Float(x + 1) * cellSize
                let south = Float(y) * cellSize
                let north = Float(y + 1) * cellSize
                var polygon = clipped(triangle, axis: 0, boundary: west, keepGreater: true)
                polygon = clipped(polygon, axis: 0, boundary: east, keepGreater: false)
                polygon = clipped(polygon, axis: 1, boundary: south, keepGreater: true)
                polygon = clipped(polygon, axis: 1, boundary: north, keepGreater: false)
                guard polygon.count >= 3 else { continue }
                for index in 1 ..< polygon.count - 1 {
                    output.append([polygon[0], polygon[index], polygon[index + 1]])
                }
            }
        }
        return output
    }

    private static func clipped(
        _ polygon: [Vertex],
        axis: Int,
        boundary: Float,
        keepGreater: Bool
    ) -> [Vertex] {
        guard let last = polygon.last else { return [] }
        var output: [Vertex] = []
        var previous = last
        var previousInside = inside(
            previous,
            axis: axis,
            boundary: boundary,
            keepGreater: keepGreater
        )
        for current in polygon {
            let currentInside = inside(
                current,
                axis: axis,
                boundary: boundary,
                keepGreater: keepGreater
            )
            if currentInside != previousInside {
                let from = previous.modelPosition[axis]
                let to = current.modelPosition[axis]
                let amount = (boundary - from) / (to - from)
                output.append(previous.interpolated(to: current, amount: amount))
            }
            if currentInside {
                output.append(current)
            }
            previous = current
            previousInside = currentInside
        }
        return output
    }

    private static func inside(
        _ vertex: Vertex,
        axis: Int,
        boundary: Float,
        keepGreater: Bool
    ) -> Bool {
        let value = vertex.modelPosition[axis]
        return keepGreater ? value >= boundary : value <= boundary
    }

    private static func hasArea(_ triangle: [Vertex]) -> Bool {
        guard triangle.count == 3 else { return false }
        let first = triangle[0].modelPosition
        let second = triangle[1].modelPosition
        let third = triangle[2].modelPosition
        let twiceArea = (second.x - first.x) * (third.y - first.y)
            - (second.y - first.y) * (third.x - first.x)
        return abs(twiceArea) > 0.001
    }
}
