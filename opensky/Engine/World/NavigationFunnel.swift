// Radius-aware string pulling for a triangle corridor. Shared-edge portals
// shrink by the capsule radius before the standard funnel runs. Door points
// split the funnel so the result cannot smooth past an authored traversal.

import simd

nonisolated struct NavigationPulledPath: Sendable {
    var waypoints: [SIMD3<Float>]
    var doorCrossings: [NavigationDoorCrossing]
}

nonisolated struct NavigationOrientedPortal: Sendable {
    let left: SIMD3<Float>
    let right: SIMD3<Float>
}

nonisolated struct NavigationFunnelInput: Sendable {
    let corridor: [NavigationTriangleID]
    let transitions: [NavigationTransition]
    let start: SIMD3<Float>
    let target: SIMD3<Float>
    let radius: Float
}

nonisolated enum NavigationFunnel {
    static func pull(
        _ input: NavigationFunnelInput,
        graph: RuntimeNavigationGraph
    ) -> NavigationPulledPath {
        var result = NavigationPulledPath(waypoints: [input.start], doorCrossings: [])
        var portals: [NavigationOrientedPortal] = []
        portals.reserveCapacity(input.transitions.count)
        var segmentStart = input.start
        for (index, transition) in input.transitions.enumerated() {
            switch transition.portal {
            case let .edge(first, second):
                guard
                    let source = graph.triangle(input.corridor[index])?.centroid,
                    let destination = graph.triangle(transition.target)?.centroid
                else { continue }
                portals.append(orientedPortal(
                    first: first,
                    second: second,
                    source: source,
                    destination: destination,
                    radius: input.radius
                ))
                appendDoorMarkers(
                    for: transition.target,
                    portals: &portals,
                    segmentStart: &segmentStart,
                    result: &result,
                    graph: graph
                )
            case let .door(reference, sourceDoor, destinationDoor):
                appendSegment(
                    from: segmentStart,
                    through: portals,
                    to: sourceDoor,
                    result: &result
                )
                let crossingIndex = result.waypoints.count - 1
                result.doorCrossings.append(NavigationDoorCrossing(
                    door: reference, waypointIndex: crossingIndex
                ))
                append(destinationDoor, to: &result.waypoints)
                segmentStart = destinationDoor
                portals.removeAll(keepingCapacity: true)
            }
        }
        appendSegment(from: segmentStart, through: portals, to: input.target, result: &result)
        return result
    }

    private static func appendDoorMarkers(
        for node: NavigationTriangleID,
        portals: inout [NavigationOrientedPortal],
        segmentStart: inout SIMD3<Float>,
        result: inout NavigationPulledPath,
        graph: RuntimeNavigationGraph
    ) {
        guard let mesh = graph.mesh(containing: node) else { return }
        for reference in mesh.doorLinksByTriangle[node.triangle] ?? [] {
            guard let door = graph.door(reference), door.destination == nil else { continue }
            appendSegment(
                from: segmentStart, through: portals, to: door.position, result: &result
            )
            result.doorCrossings.append(NavigationDoorCrossing(
                door: reference, waypointIndex: result.waypoints.count - 1
            ))
            segmentStart = door.position
            portals.removeAll(keepingCapacity: true)
        }
    }

    private static func appendSegment(
        from start: SIMD3<Float>,
        through portals: [NavigationOrientedPortal],
        to target: SIMD3<Float>,
        result: inout NavigationPulledPath
    ) {
        for point in stringPull(start: start, portals: portals, target: target).dropFirst() {
            append(point, to: &result.waypoints)
        }
    }

    private static func orientedPortal(
        first: SIMD3<Float>,
        second: SIMD3<Float>,
        source: SIMD3<Float>,
        destination: SIMD3<Float>,
        radius: Float
    ) -> NavigationOrientedPortal {
        let direction = SIMD2(destination.x - source.x, destination.y - source.y)
        let firstSide = NavigationGeometry.cross(
            direction, SIMD2(first.x - source.x, first.y - source.y)
        )
        let secondSide = NavigationGeometry.cross(
            direction, SIMD2(second.x - source.x, second.y - source.y)
        )
        // `stringPull` follows Recast's portal convention, whose signed-area
        // helper has the opposite sign from our conventional XY cross.
        let oriented = firstSide <= secondSide ? (first, second) : (second, first)
        let width = simd_distance(oriented.0, oriented.1)
        guard width > NavigationGeometry.epsilon else {
            let midpoint = (oriented.0 + oriented.1) / 2
            return NavigationOrientedPortal(left: midpoint, right: midpoint)
        }
        let shrink = min(max(0, radius), width / 2)
        let directionToRight = (oriented.1 - oriented.0) / width
        return NavigationOrientedPortal(
            left: oriented.0 + directionToRight * shrink,
            right: oriented.1 - directionToRight * shrink
        )
    }

    /// The simple-stupid funnel algorithm with deterministic equality tests.
    private static func stringPull(
        start: SIMD3<Float>,
        portals: [NavigationOrientedPortal],
        target: SIMD3<Float>
    ) -> [SIMD3<Float>] {
        let all = portals + [NavigationOrientedPortal(left: target, right: target)]
        var result = [start]
        var apex = start
        var left = start
        var right = start
        var apexIndex = 0
        var leftIndex = 0
        var rightIndex = 0
        var index = 0
        while index < all.count {
            let nextLeft = all[index].left
            let nextRight = all[index].right
            if area(apex, right, nextRight) <= 0 {
                if same(apex, right) || area(apex, left, nextRight) > 0 {
                    right = nextRight
                    rightIndex = index
                } else {
                    append(left, to: &result)
                    apex = left
                    apexIndex = leftIndex
                    left = apex
                    right = apex
                    leftIndex = apexIndex
                    rightIndex = apexIndex
                    index = apexIndex
                }
            }
            if area(apex, left, nextLeft) >= 0 {
                if same(apex, left) || area(apex, right, nextLeft) < 0 {
                    left = nextLeft
                    leftIndex = index
                } else {
                    append(right, to: &result)
                    apex = right
                    apexIndex = rightIndex
                    left = apex
                    right = apex
                    leftIndex = apexIndex
                    rightIndex = apexIndex
                    index = apexIndex
                }
            }
            index += 1
        }
        append(target, to: &result)
        return result
    }

    private static func area(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>
    ) -> Float {
        NavigationGeometry.cross(
            SIMD2(second.x - first.x, second.y - first.y),
            SIMD2(third.x - first.x, third.y - first.y)
        )
    }

    private static func same(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
        simd_distance_squared(lhs, rhs) <= NavigationGeometry.epsilon
    }

    private static func append(_ point: SIMD3<Float>, to result: inout [SIMD3<Float>]) {
        guard result.last.map({ !same($0, point) }) ?? true else { return }
        result.append(point)
    }
}
