// Resident, queryable navigation graph (issue #200). Each cell contributes
// immutable NAVM geometry. Cross-navmesh edges and teleport doors resolve at
// query time, so residency changes need no callback web or adjacency rebuild.

import OpenSkyFormats
import simd

nonisolated public struct RuntimeNavigationTriangle: Sendable {
    public let vertices: NavigationTriangleVertices
    public let centroid: SIMD3<Float>
    public let neighbors: SIMD3<Int16>
    public let flags: NavmeshGeometry.TriangleFlags
    public let isDegenerate: Bool
}

nonisolated public struct NavigationTriangleVertices: Sendable {
    public let first: SIMD3<Float>
    public let second: SIMD3<Float>
    public let third: SIMD3<Float>
}

nonisolated public struct RuntimeNavigationMesh: Sendable {
    public let formID: FormID
    public let cell: CellSceneLocation
    public let triangles: [RuntimeNavigationTriangle]
    public let edgeLinks: [NavmeshGeometry.EdgeLink]
    public let doorLinksByTriangle: [Int: [FormID]]

    public init(navmesh: Navmesh, cell: CellSceneLocation) {
        formID = navmesh.formID
        self.cell = cell
        edgeLinks = navmesh.geometry.edgeLinks
        triangles = navmesh.geometry.triangles.map { triangle in
            let first = navmesh.geometry.vertices[Int(triangle.vertices.x)]
            let second = navmesh.geometry.vertices[Int(triangle.vertices.y)]
            let third = navmesh.geometry.vertices[Int(triangle.vertices.z)]
            let twiceArea = NavigationGeometry.cross(
                SIMD2(second.x - first.x, second.y - first.y),
                SIMD2(third.x - first.x, third.y - first.y)
            )
            return RuntimeNavigationTriangle(
                vertices: NavigationTriangleVertices(
                    first: first,
                    second: second,
                    third: third
                ),
                centroid: (first + second + third) / 3,
                neighbors: triangle.neighbors,
                flags: triangle.flags,
                isDegenerate: abs(twiceArea) <= NavigationGeometry.epsilon
            )
        }
        doorLinksByTriangle = Dictionary(
            grouping: navmesh.geometry.doorLinks.filter { $0.triangle >= 0 },
            by: { Int($0.triangle) }
        ).mapValues { links in links.map(\.door).sorted { $0.rawValue < $1.rawValue } }
    }

    public func triangle(_ index: Int) -> RuntimeNavigationTriangle? {
        guard triangles.indices.contains(index) else { return nil }
        return triangles[index]
    }
}

nonisolated public struct RuntimeNavigationDoor: Sendable {
    public let position: SIMD3<Float>
    public let destination: FormID?
}

nonisolated public struct RuntimeNavigationGraph: Sendable {
    public private(set) var installedCells: [CellSceneLocation: UInt64] = [:]
    private var cellNavmeshes: [CellSceneLocation: [UInt32]] = [:]
    private var navmeshes: [UInt32: RuntimeNavigationMesh] = [:]
    private var doors: [UInt32: RuntimeNavigationDoor] = [:]
    private var cellDoors: [CellSceneLocation: [UInt32]] = [:]
    private var doorTriangles: [UInt32: [NavigationTriangleID]] = [:]
    private var scratch = NavigationQueryScratch()

    public var isEmpty: Bool {
        navmeshes.isEmpty
    }

    public var triangleCount: Int {
        navmeshes.values.reduce(0) { $0 + $1.triangles.count }
    }

    public var hasTeleportDoors: Bool {
        doors.values.contains { $0.destination != nil }
    }

    public mutating func setCell(_ location: CellSceneLocation, scene: CellScene) {
        removeCell(location)
        installedCells[location] = scene.stateSequence
        let meshIDs = scene.navmeshes.map(\.formID.rawValue)
        cellNavmeshes[location] = meshIDs
        for navmesh in scene.navmeshes {
            let runtime = RuntimeNavigationMesh(navmesh: navmesh, cell: location)
            navmeshes[navmesh.formID.rawValue] = runtime
            for (triangle, doorIDs) in runtime.doorLinksByTriangle {
                let node = NavigationTriangleID(navmesh: navmesh.formID, triangle: triangle)
                for doorID in doorIDs {
                    doorTriangles[doorID.rawValue, default: []].append(node)
                    doorTriangles[doorID.rawValue]?.sort()
                }
            }
        }
        installDoors(from: scene, at: location)
    }

    public mutating func removeCell(_ location: CellSceneLocation) {
        installedCells.removeValue(forKey: location)
        for meshID in cellNavmeshes.removeValue(forKey: location) ?? [] {
            guard let removed = navmeshes.removeValue(forKey: meshID) else { continue }
            for (triangle, doorIDs) in removed.doorLinksByTriangle {
                let node = NavigationTriangleID(navmesh: removed.formID, triangle: triangle)
                for doorID in doorIDs {
                    doorTriangles[doorID.rawValue]?.removeAll { $0 == node }
                    if doorTriangles[doorID.rawValue]?.isEmpty == true {
                        doorTriangles.removeValue(forKey: doorID.rawValue)
                    }
                }
            }
        }
        for doorID in cellDoors.removeValue(forKey: location) ?? [] {
            doors.removeValue(forKey: doorID)
        }
    }

    public mutating func retainCells(_ locations: Set<CellSceneLocation>) {
        for location in Array(installedCells.keys) where !locations.contains(location) {
            removeCell(location)
        }
    }

    public func projection(
        of point: SIMD3<Float>,
        searchRadius: Float = NavigationPathQuery.defaultProjectionRadius
    ) -> NavigationProjectionResult {
        var nearest: NavigationProjection?
        let radius = max(0, searchRadius)
        for mesh in navmeshes.values {
            for index in mesh.triangles.indices {
                let triangle = mesh.triangles[index]
                guard !triangle.isDegenerate, !triangle.flags.contains(.deleted) else { continue }
                let position = NavigationGeometry.closestPoint(on: triangle, to: point)
                let distance = simd_distance(position, point)
                guard distance <= radius else { continue }
                let candidate = NavigationProjection(
                    triangle: NavigationTriangleID(navmesh: mesh.formID, triangle: index),
                    position: position,
                    distance: distance
                )
                if Self.projection(candidate, precedes: nearest) {
                    nearest = candidate
                }
            }
        }
        return nearest.map(NavigationProjectionResult.hit) ?? .miss
    }

    public func pathIsCurrent(
        _ path: NavigationPath,
        target: SIMD3<Float>,
        targetMoveTolerance: Float = NavigationPathQuery.defaultTargetMoveTolerance
    ) -> Bool {
        let cellsAreCurrent = path.cellSequences.allSatisfy { location, sequence in
            installedCells[location] == sequence
        }
        return cellsAreCurrent
            && simd_distance(path.target, target) <= max(0, targetMoveTolerance)
    }

    public func mesh(containing node: NavigationTriangleID) -> RuntimeNavigationMesh? {
        navmeshes[node.navmesh.rawValue]
    }

    public func door(_ reference: FormID) -> RuntimeNavigationDoor? {
        doors[reference.rawValue]
    }

    public func triangles(atDoor reference: FormID) -> [NavigationTriangleID] {
        doorTriangles[reference.rawValue] ?? []
    }

    public func cell(at point: SIMD3<Float>) -> CellSceneLocation? {
        guard case let .hit(projection) = projection(of: point) else { return nil }
        return mesh(containing: projection.triangle)?.cell
    }

    public mutating func findPath(_ query: NavigationPathQuery) -> NavigationPathResult {
        var workspace = NavigationQueryScratch()
        swap(&workspace, &scratch)
        let result = NavigationPathfinder.findPath(query, in: self, scratch: &workspace)
        swap(&workspace, &scratch)
        return result
    }

    private mutating func installDoors(from scene: CellScene, at location: CellSceneLocation) {
        var identifiers: [UInt32] = []
        for interaction in scene.interactions.values where interaction.action == .open {
            let reference = interaction.reference.rawValue
            doors[reference] = RuntimeNavigationDoor(
                position: interaction.position,
                destination: scene.doors.first { $0.reference == interaction.reference }?
                    .destination.door
            )
            identifiers.append(reference)
        }
        for door in scene.doors where doors[door.reference.rawValue] == nil {
            doors[door.reference.rawValue] = RuntimeNavigationDoor(
                position: door.position, destination: door.destination.door
            )
            identifiers.append(door.reference.rawValue)
        }
        cellDoors[location] = identifiers.sorted()
    }

    private static func projection(
        _ candidate: NavigationProjection,
        precedes current: NavigationProjection?
    ) -> Bool {
        guard let current else { return true }
        if candidate.distance != current.distance {
            return candidate.distance < current.distance
        }
        return candidate.triangle < current.triangle
    }

    public init(
        installedCells: [CellSceneLocation: UInt64] = [:],
        cellNavmeshes: [CellSceneLocation: [UInt32]] = [:],
        navmeshes: [UInt32: RuntimeNavigationMesh] = [:],
        doors: [UInt32: RuntimeNavigationDoor] = [:],
        cellDoors: [CellSceneLocation: [UInt32]] = [:],
        doorTriangles: [UInt32: [NavigationTriangleID]] = [:],
        scratch: NavigationQueryScratch = NavigationQueryScratch()
    ) {
        self.installedCells = installedCells
        self.cellNavmeshes = cellNavmeshes
        self.navmeshes = navmeshes
        self.doors = doors
        self.cellDoors = cellDoors
        self.doorTriangles = doorTriangles
        self.scratch = scratch
    }
}

nonisolated extension RuntimeNavigationGraph {
    /// Appends the resident navmesh fill and latest valid path using the same
    /// graph the pathfinder queries. A small Z lift prevents coplanar floor
    /// geometry from producing unstable depth ties.
    public func appendWorldOverlay(
        context: WorldOverlayFrameContext,
        path: NavigationPath?,
        to list: inout WorldOverlayDrawList
    ) {
        if context.navmeshOverlayEnabled {
            appendResidentNavmeshes(to: &list)
        }
        if
            context.pathOverlayEnabled,
            let path,
            pathIsCurrent(path, target: path.target)
        {
            appendPath(path, to: &list)
        }
    }

    private func appendResidentNavmeshes(to list: inout WorldOverlayDrawList) {
        let meshes = navmeshes.values.sorted { left, right in
            if left.cell != right.cell {
                return CellSceneLocation.isOrderedBefore(left.cell, right.cell)
            }
            return left.formID.rawValue < right.formID.rawValue
        }
        for mesh in meshes {
            let color = Self.cellColor(mesh.cell)
            for triangle in mesh.triangles
                where !triangle.isDegenerate && !triangle.flags.contains(.deleted)
            {
                list.addTriangle(
                    Self.lift(triangle.vertices.first),
                    Self.lift(triangle.vertices.second),
                    Self.lift(triangle.vertices.third),
                    color: color
                )
            }
        }
    }

    private func appendPath(_ path: NavigationPath, to list: inout WorldOverlayDrawList) {
        let corridorColor = SIMD4<Float>(1, 0.28, 0.04, 0.42)
        for identifier in path.corridor {
            guard let triangle = triangle(identifier), !triangle.isDegenerate else { continue }
            list.addTriangle(
                Self.lift(triangle.vertices.first, amount: 8),
                Self.lift(triangle.vertices.second, amount: 8),
                Self.lift(triangle.vertices.third, amount: 8),
                color: corridorColor
            )
        }
        list.addPolyline(
            path.waypoints.map { Self.lift($0, amount: 12) },
            color: SIMD4(1, 0.95, 0.12, 1)
        )
    }

    private static func lift(_ position: SIMD3<Float>, amount: Float = 4) -> SIMD3<Float> {
        position + SIMD3(0, 0, amount)
    }

    /// Eight high-contrast translucent fills, selected by a deterministic
    /// cell-identity hash. Every navmesh in one cell receives the same color.
    private static func cellColor(_ cell: CellSceneLocation) -> SIMD4<Float> {
        let palette: [SIMD3<Float>] = [
            SIMD3(0.12, 0.78, 1), SIMD3(0.28, 1, 0.45),
            SIMD3(0.82, 0.42, 1), SIMD3(1, 0.62, 0.12),
            SIMD3(0.08, 0.92, 0.78), SIMD3(1, 0.3, 0.52),
            SIMD3(0.55, 0.72, 1), SIMD3(0.78, 1, 0.18)
        ]
        let index: Int
        switch cell {
        case let .exterior(coordinate):
            let x = UInt32(bitPattern: coordinate.x)
            let y = UInt32(bitPattern: coordinate.y)
            index = Int((x &* 1_664_525 &+ y &* 1_013_904_223) % UInt32(palette.count))
        case let .interior(formID):
            index = Int(formID.rawValue % UInt32(palette.count))
        }
        return SIMD4(palette[index], 0.22)
    }
}
