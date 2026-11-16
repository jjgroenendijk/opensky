// Global wildcards (`FLAG_IS_GLOBAL_WILDCARD`): a wildcard of a nested machine
// that fires while that machine is not active. Each ancestor machine moves into
// the state that holds it, and the nested machines then start in the wildcard's
// target. The rule crosses a behavior reference: a wildcard in a referenced file
// moves the machines of the file that refers to it.
// Rule and evidence: docs/engine/behavior-state-machines.md.

import Foundation
public import OpenSkyFormatsAnimation

/// A global wildcard as one ancestor machine sees it: which of its own states
/// to enter, then the start state of each machine below, outermost first.
nonisolated struct BehaviorGlobalWildcardRoute {
    let stateId: Int
    let nestedStateIds: [Int]
    let owner: HKBStateMachine
    let info: HKBStateMachineTransitionInfo
    /// The behavior references from this graph down to the graph that holds `owner`;
    /// empty when this graph holds it. That graph takes the wildcard itself once it
    /// runs, so no start state crosses over. A path, not an instance, so every actor
    /// over the same file shares the route.
    var holderPath: [String] = []

    func entered(through stateId: Int, nested: [Int]) -> BehaviorGlobalWildcardRoute {
        BehaviorGlobalWildcardRoute(
            stateId: stateId, nestedStateIds: nested, owner: owner, info: info,
            holderPath: holderPath
        )
    }
}

/// Which machine a shared table is for. A reference that would close a cycle is
/// dropped, so the same machine can have other routes under another ancestry.
nonisolated struct BehaviorGlobalWildcardTableKey: Hashable {
    let machine: HKXPointerTarget
    let ancestry: Set<String>
    let followsReferences: Bool
}

/// The global wildcard routes of one machine, and which of them each event can fire.
nonisolated struct BehaviorGlobalWildcardTable {
    let routes: [BehaviorGlobalWildcardRoute]
    /// Event id in the graph that runs the machine -> indices into `routes`, in order.
    let routesByEvent: [Int: [Int]]
}

nonisolated extension BehaviorGraphInstance.StateMachines {
    /// Takes the first eligible global wildcard found below a state other than
    /// the current one. The current state's machines see their own wildcards.
    /// Only the routes of the events active in this update are tested.
    func selectGlobalWildcard(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine,
        at target: HKXPointerTarget
    ) -> Bool {
        let active = graph.events.active
        guard !active.isEmpty else { return false }
        let table = globalWildcardTable(of: machine, at: target)
        var bestIndex: Int?
        for event in active {
            for index in table.routesByEvent[event.id] ?? [] {
                let route = table.routes[index]
                guard route.stateId != state.currentStateId, permitsRoute(route) else { continue }
                if let current = bestIndex {
                    let held = table.routes[current].info.priority
                    guard
                        route.info.priority > held
                        || (route.info.priority == held && index < current)
                    else { continue }
                }
                bestIndex = index
            }
        }
        guard let bestIndex else { return false }
        let best = table.routes[bestIndex]
        guard stateInfo(of: machine, id: best.stateId) != nil else { return false }
        if let running = state.transition, running.refuses(best.info) {
            return false
        }
        var effect = holderMachines(of: best)?.effect(for: best.info)
        effect?.priority = best.info.priority
        effect?.interrupted = state.transition.map { [$0] } ?? []
        effect?.trim(to: machine.maxSimultaneousTransitions)
        switchState(&state, to: best.stateId, machine: machine, transition: effect)
        graph.pendingNestedStateIds = best.nestedStateIds
        return true
    }

    private func permitsRoute(_ route: BehaviorGlobalWildcardRoute) -> Bool {
        holderMachines(of: route)?.permits(route) ?? false
    }

    /// The state machines of the graph that holds the route's machine.
    private func holderMachines(
        of route: BehaviorGlobalWildcardRoute
    ) -> BehaviorGraphInstance.StateMachines? {
        var holder = graph
        for name in route.holderPath {
            guard let child = holder.childGraphs.referencedGraph(named: name) else { return nil }
            holder = child
        }
        return holder.stateMachines
    }

    /// The routes of `machine`, indexed by the id of their event in this graph.
    /// Event ids differ per file, so a route from a referenced file is matched by
    /// name once, here, and not in every update. Graphs over the same file share
    /// the table, so only the first actor of a race walks the referenced files.
    func globalWildcardTable(
        of machine: HKBStateMachine,
        at target: HKXPointerTarget
    ) -> BehaviorGlobalWildcardTable {
        if let cached = graph.machineMemory.globalWildcardTables[target] {
            return cached
        }
        let key = BehaviorGlobalWildcardTableKey(
            machine: target, ancestry: graph.referenceAncestry,
            followsReferences: graph.references != nil
        )
        if let shared = graph.fileCaches?.globalWildcardTables[key] {
            graph.machineMemory.globalWildcardTables[target] = shared
            return shared
        }
        let routes = globalWildcardRoutes(of: machine, at: target)
        var byEvent: [Int: [Int]] = [:]
        for (index, route) in routes.enumerated() {
            guard let eventId = localEventId(of: route) else { continue }
            byEvent[eventId, default: []].append(index)
        }
        let table = BehaviorGlobalWildcardTable(routes: routes, routesByEvent: byEvent)
        graph.machineMemory.globalWildcardTables[target] = table
        graph.fileCaches?.globalWildcardTables[key] = table
        return table
    }

    private func localEventId(of route: BehaviorGlobalWildcardRoute) -> Int? {
        let eventId = route.info.eventId
        guard !route.holderPath.isEmpty else { return eventId >= 0 ? eventId : nil }
        guard let holder = holderMachines(of: route)?.graph else { return nil }
        let names = holder.events.names
        guard names.indices.contains(eventId), let name = names[eventId] else { return nil }
        return graph.events.index(of: name)
    }

    /// Whether the wildcard itself may fire, apart from its event.
    private func permits(_ route: BehaviorGlobalWildcardRoute) -> Bool {
        let info = route.info
        guard
            info.flags & BehaviorTransitionFlag.disabled == 0,
            stateInfo(of: route.owner, id: info.toStateId) != nil
        else { return false }
        return isIntervalOpen(info) && isConditionMet(info)
    }

    // MARK: - Routes

    /// Every global wildcard below `machine`, built once per machine.
    func globalWildcardRoutes(
        of machine: HKBStateMachine,
        at target: HKXPointerTarget,
        depth: Int = 0
    ) -> [BehaviorGlobalWildcardRoute] {
        if let cached = graph.machineMemory.globalWildcardRouteCache[target] {
            return cached
        }
        // Cached empty first, so a machine nested inside itself ends the walk.
        graph.machineMemory.globalWildcardRouteCache[target] = []
        guard depth < BehaviorGraphInstance.maximumDepth else { return [] }
        var routes: [BehaviorGlobalWildcardRoute] = []
        for case let stateTarget? in machine.states {
            guard let info = graph.object(at: stateTarget, as: HKBStateMachineStateInfo.self) else {
                continue
            }
            routes += globalWildcardRoutes(below: info.generator, depth: depth).map {
                $0.entered(through: info.stateId, nested: $0.nestedStateIds)
            }
        }
        graph.machineMemory.globalWildcardRouteCache[target] = routes
        return routes
    }

    /// Every global wildcard below the generator at `root`. `stateId` is unused: the
    /// caller sets the state that holds `root`.
    func globalWildcardRoutes(
        below root: HKXPointerTarget?,
        depth: Int
    ) -> [BehaviorGlobalWildcardRoute] {
        let below = nodes(below: root)
        var routes: [BehaviorGlobalWildcardRoute] = []
        for nested in below.machines {
            routes += ownGlobalWildcards(of: nested.machine).map {
                route($0, from: -1, owner: nested.machine)
            }
            routes += globalWildcardRoutes(
                of: nested.machine, at: nested.target, depth: depth + 1
            ).map { $0.entered(through: -1, nested: [$0.stateId] + $0.nestedStateIds) }
        }
        for name in below.references {
            guard let child = graph.childGraphs.referencedGraph(named: name) else { continue }
            routes += child.stateMachines.globalWildcardRoutes(below: child.root, depth: depth + 1)
                .map {
                    var route = $0.entered(through: -1, nested: [])
                    route.holderPath = [name] + $0.holderPath
                    return route
                }
        }
        return routes
    }

    private func route(
        _ info: HKBStateMachineTransitionInfo,
        from stateId: Int,
        owner: HKBStateMachine
    ) -> BehaviorGlobalWildcardRoute {
        var nested = [info.toStateId]
        if info.flags & BehaviorTransitionFlag.toNestedStateIsValid != 0 {
            nested.append(info.toNestedStateId)
        }
        return BehaviorGlobalWildcardRoute(
            stateId: stateId, nestedStateIds: nested, owner: owner, info: info
        )
    }

    private func ownGlobalWildcards(of machine: HKBStateMachine)
        -> [HKBStateMachineTransitionInfo]
    {
        guard
            let target = machine.wildcardTransitions,
            let array = graph.object(at: target, as: HKBStateMachineTransitionInfoArray.self)
        else {
            return []
        }
        return array.transitions.filter {
            $0.flags & BehaviorTransitionFlag.globalWildcard != 0
        }
    }

    private struct NodesBelow {
        var machines: [(machine: HKBStateMachine, target: HKXPointerTarget)] = []
        var references: [String] = []
    }

    /// The first machines on each path down from `root`, and the behavior files
    /// referred to above them. The walk stops at a machine, because that machine's
    /// own routes cover what lies below it.
    private func nodes(below root: HKXPointerTarget?) -> NodesBelow {
        var found = NodesBelow()
        var visited: Set<HKXPointerTarget> = []
        var stack = root.map { [$0] } ?? []
        while let target = stack.popLast() {
            guard visited.insert(target).inserted, let node = graph.compiledNode(at: target) else {
                continue
            }
            if let machine = node.object as? HKBStateMachine {
                found.machines.append((machine, target))
                continue
            }
            if let name = (node.object as? HKBBehaviorReferenceGenerator)?.behaviorName {
                found.references.append(name)
                continue
            }
            stack += node.children.reversed()
        }
        return found
    }
}
