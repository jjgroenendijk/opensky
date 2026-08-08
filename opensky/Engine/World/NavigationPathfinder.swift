// Deterministic A* over resident navmesh triangles (issue #200). The open
// heap and score maps retain capacity across queries. A shared-edge step costs
// centroid -> edge midpoint -> next centroid; the heuristic is straight-line
// centroid distance, or zero when a resident teleport can make world-space
// distance non-admissible.

import simd

nonisolated enum NavigationPortal: Equatable, Sendable {
    case edge(SIMD3<Float>, SIMD3<Float>)
    case door(reference: FormID, source: SIMD3<Float>, destination: SIMD3<Float>)
}

nonisolated struct NavigationTransition: Equatable, Sendable {
    let target: NavigationTriangleID
    let portal: NavigationPortal
}

nonisolated struct NavigationCameFrom: Sendable {
    let node: NavigationTriangleID
    let portal: NavigationPortal
}

nonisolated struct NavigationOpenEntry: Sendable {
    let node: NavigationTriangleID
    let cost: Float
    let heuristic: Float

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.cost != rhs.cost {
            return lhs.cost < rhs.cost
        }
        if lhs.heuristic != rhs.heuristic {
            return lhs.heuristic < rhs.heuristic
        }
        return lhs.node < rhs.node
    }
}

nonisolated struct NavigationQueryScratch: Sendable {
    var openHeap: [NavigationOpenEntry] = []
    var transitions: [NavigationTransition] = []
    var cameFrom: [NavigationTriangleID: NavigationCameFrom] = [:]
    var costs: [NavigationTriangleID: Float] = [:]
    var closed: Set<NavigationTriangleID> = []
    var corridor: [NavigationTriangleID] = []
    var corridorTransitions: [NavigationTransition] = []

    mutating func reset() {
        openHeap.removeAll(keepingCapacity: true)
        transitions.removeAll(keepingCapacity: true)
        cameFrom.removeAll(keepingCapacity: true)
        costs.removeAll(keepingCapacity: true)
        closed.removeAll(keepingCapacity: true)
        corridor.removeAll(keepingCapacity: true)
        corridorTransitions.removeAll(keepingCapacity: true)
    }

    mutating func push(_ entry: NavigationOpenEntry) {
        openHeap.append(entry)
        var child = openHeap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard NavigationOpenEntry.precedes(openHeap[child], openHeap[parent]) else { break }
            openHeap.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> NavigationOpenEntry? {
        guard !openHeap.isEmpty else { return nil }
        if openHeap.count == 1 {
            return openHeap.removeLast()
        }
        let result = openHeap[0]
        openHeap[0] = openHeap.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < openHeap.count else { break }
            let right = left + 1
            let child = right < openHeap.count
                && NavigationOpenEntry.precedes(openHeap[right], openHeap[left]) ? right : left
            guard NavigationOpenEntry.precedes(openHeap[child], openHeap[parent]) else { break }
            openHeap.swapAt(parent, child)
            parent = child
        }
        return result
    }
}

nonisolated enum NavigationPathfinder {
    static func findPath(
        _ query: NavigationPathQuery,
        in graph: RuntimeNavigationGraph,
        scratch: inout NavigationQueryScratch
    ) -> NavigationPathResult {
        guard
            case let .hit(start) = graph.projection(
                of: query.start, searchRadius: query.projectionRadius
            ) else { return .miss(.startProjection) }
        guard
            case let .hit(target) = graph.projection(
                of: query.target, searchRadius: query.projectionRadius
            ) else { return .miss(.targetProjection) }

        scratch.reset()
        scratch.costs[start.triangle] = 0
        let firstHeuristic = heuristic(start.triangle, target: target.triangle, in: graph)
        scratch.push(NavigationOpenEntry(
            node: start.triangle, cost: firstHeuristic, heuristic: firstHeuristic
        ))

        var expanded = 0
        while let entry = scratch.pop() {
            guard !scratch.closed.contains(entry.node) else { continue }
            scratch.closed.insert(entry.node)
            expanded += 1
            if entry.node == target.triangle {
                return makePath(
                    endpoints: NavigationProjectedEndpoints(start: start, target: target),
                    query: query,
                    expanded: expanded,
                    graph: graph,
                    scratch: &scratch
                )
            }
            expand(entry.node, target: target.triangle, graph: graph, scratch: &scratch)
        }
        return .miss(.disconnected)
    }

    private static func expand(
        _ node: NavigationTriangleID,
        target: NavigationTriangleID,
        graph: RuntimeNavigationGraph,
        scratch: inout NavigationQueryScratch
    ) {
        guard let baseCost = scratch.costs[node] else { return }
        graph.transitions(from: node, into: &scratch.transitions)
        for transition in scratch.transitions where !scratch.closed.contains(transition.target) {
            let newCost = baseCost + transitionCost(transition, from: node, in: graph)
            if let oldCost = scratch.costs[transition.target], newCost >= oldCost {
                continue
            }
            scratch.costs[transition.target] = newCost
            scratch.cameFrom[transition.target] = NavigationCameFrom(
                node: node, portal: transition.portal
            )
            let estimate = heuristic(transition.target, target: target, in: graph)
            scratch.push(NavigationOpenEntry(
                node: transition.target,
                cost: newCost + estimate,
                heuristic: estimate
            ))
        }
    }

    private static func transitionCost(
        _ transition: NavigationTransition,
        from source: NavigationTriangleID,
        in graph: RuntimeNavigationGraph
    ) -> Float {
        guard
            let sourceCenter = graph.triangle(source)?.centroid,
            let targetCenter = graph.triangle(transition.target)?.centroid
        else { return .greatestFiniteMagnitude }
        switch transition.portal {
        case let .edge(first, second):
            let midpoint = (first + second) / 2
            return simd_distance(sourceCenter, midpoint) + simd_distance(midpoint, targetCenter)
        case let .door(_, sourceDoor, targetDoor):
            return simd_distance(sourceCenter, sourceDoor) + simd_distance(targetDoor, targetCenter)
        }
    }

    private static func heuristic(
        _ node: NavigationTriangleID,
        target: NavigationTriangleID,
        in graph: RuntimeNavigationGraph
    ) -> Float {
        guard !graph.hasTeleportDoors else { return 0 }
        guard
            let start = graph.triangle(node)?.centroid,
            let finish = graph.triangle(target)?.centroid
        else { return 0 }
        return simd_distance(start, finish)
    }

    private static func makePath(
        endpoints: NavigationProjectedEndpoints,
        query: NavigationPathQuery,
        expanded: Int,
        graph: RuntimeNavigationGraph,
        scratch: inout NavigationQueryScratch
    ) -> NavigationPathResult {
        scratch.corridor.append(endpoints.target.triangle)
        var current = endpoints.target.triangle
        while current != endpoints.start.triangle {
            guard let previous = scratch.cameFrom[current] else {
                return .miss(.disconnected)
            }
            scratch.corridorTransitions.append(NavigationTransition(
                target: current, portal: previous.portal
            ))
            current = previous.node
            scratch.corridor.append(current)
        }
        scratch.corridor.reverse()
        scratch.corridorTransitions.reverse()
        let pulled = NavigationFunnel.pull(NavigationFunnelInput(
            corridor: scratch.corridor,
            transitions: scratch.corridorTransitions,
            start: endpoints.start.position,
            target: endpoints.target.position,
            radius: query.capsuleRadius
        ), graph: graph)
        var sequences: [CellSceneLocation: UInt64] = [:]
        for node in scratch.corridor {
            guard
                let cell = graph.mesh(containing: node)?.cell,
                let sequence = graph.installedCells[cell]
            else { continue }
            sequences[cell] = sequence
        }
        return .path(NavigationPath(
            waypoints: pulled.waypoints,
            doorCrossings: pulled.doorCrossings,
            stats: NavigationPathStats(
                nodesExpanded: expanded,
                corridorTriangleCount: scratch.corridor.count
            ),
            corridor: scratch.corridor,
            cellSequences: sequences,
            target: query.target
        ))
    }
}

nonisolated private struct NavigationProjectedEndpoints {
    let start: NavigationProjection
    let target: NavigationProjection
}

nonisolated extension RuntimeNavigationGraph {
    func triangle(_ node: NavigationTriangleID) -> RuntimeNavigationTriangle? {
        mesh(containing: node)?.triangle(node.triangle)
    }

    func transitions(
        from node: NavigationTriangleID,
        into result: inout [NavigationTransition]
    ) {
        result.removeAll(keepingCapacity: true)
        guard let mesh = mesh(containing: node), let triangle = mesh.triangle(node.triangle) else {
            return
        }
        let linkFlags: [NavmeshGeometry.TriangleFlags] = [
            .edge01Link, .edge12Link, .edge20Link
        ]
        for edge in 0 ..< 3 {
            let neighbor = triangle.neighbors[edge]
            guard neighbor >= 0 else { continue }
            let target: NavigationTriangleID
            if triangle.flags.contains(linkFlags[edge]) {
                guard mesh.edgeLinks.indices.contains(Int(neighbor)) else { continue }
                let link = mesh.edgeLinks[Int(neighbor)]
                guard link.triangle >= 0 else { continue }
                target = NavigationTriangleID(
                    navmesh: link.navmesh, triangle: Int(link.triangle)
                )
            } else {
                target = NavigationTriangleID(navmesh: node.navmesh, triangle: Int(neighbor))
            }
            guard
                let targetTriangle = self.triangle(target),
                !targetTriangle.isDegenerate,
                !targetTriangle.flags.contains(.deleted)
            else { continue }
            let edgeVertices = Self.edge(edge, of: triangle)
            result.append(NavigationTransition(
                target: target,
                portal: .edge(edgeVertices.0, edgeVertices.1)
            ))
        }
        appendDoorTransitions(from: node, mesh: mesh, triangle: triangle, into: &result)
        result.sort(by: Self.transitionPrecedes)
    }

    private func appendDoorTransitions(
        from node: NavigationTriangleID,
        mesh: RuntimeNavigationMesh,
        triangle: RuntimeNavigationTriangle,
        into result: inout [NavigationTransition]
    ) {
        for reference in mesh.doorLinksByTriangle[node.triangle] ?? [] {
            guard
                let sourceDoor = door(reference),
                let destination = sourceDoor.destination,
                let targetDoor = door(destination)
            else { continue }
            for target in triangles(atDoor: destination) {
                guard target != node, let targetTriangle = self.triangle(target) else { continue }
                guard
                    !targetTriangle.isDegenerate,
                    !targetTriangle.flags.contains(.deleted)
                else { continue }
                result.append(NavigationTransition(
                    target: target,
                    portal: .door(
                        reference: reference,
                        source: sourceDoor.position,
                        destination: targetDoor.position
                    )
                ))
            }
        }
    }

    private static func edge(
        _ index: Int,
        of triangle: RuntimeNavigationTriangle
    ) -> (SIMD3<Float>, SIMD3<Float>) {
        switch index {
        case 0: (triangle.vertices.first, triangle.vertices.second)
        case 1: (triangle.vertices.second, triangle.vertices.third)
        default: (triangle.vertices.third, triangle.vertices.first)
        }
    }

    private static func transitionPrecedes(
        _ lhs: NavigationTransition,
        _ rhs: NavigationTransition
    ) -> Bool {
        if lhs.target != rhs.target {
            return lhs.target < rhs.target
        }
        switch (lhs.portal, rhs.portal) {
        case let (.door(left, _, _), .door(right, _, _)):
            return left.rawValue < right.rawValue
        case (.edge, .door):
            return true
        case (.door, .edge):
            return false
        case let (.edge(leftFirst, leftSecond), .edge(rightFirst, rightSecond)):
            if leftFirst != rightFirst {
                return (leftFirst.x, leftFirst.y, leftFirst.z)
                    < (rightFirst.x, rightFirst.y, rightFirst.z)
            }
            return (leftSecond.x, leftSecond.y, leftSecond.z)
                < (rightSecond.x, rightSecond.y, rightSecond.z)
        }
    }
}
