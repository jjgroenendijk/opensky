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
    /// The referenced graph that holds `owner`; nil when this graph holds it. That
    /// graph takes the wildcard itself once it runs, so no start state crosses over.
    var holder: BehaviorGraphInstance?

    func entered(through stateId: Int, nested: [Int]) -> BehaviorGlobalWildcardRoute {
        BehaviorGlobalWildcardRoute(
            stateId: stateId, nestedStateIds: nested, owner: owner, info: info, holder: holder
        )
    }
}

nonisolated extension BehaviorGraphInstance.StateMachines {
    /// Takes the first eligible global wildcard found below a state other than
    /// the current one. The current state's machines see their own wildcards.
    func selectGlobalWildcard(
        _ state: inout BehaviorMachineState,
        machine: HKBStateMachine,
        at target: HKXPointerTarget
    ) -> Bool {
        let routes = globalWildcardRoutes(of: machine, at: target)
        var best: BehaviorGlobalWildcardRoute?
        for route in routes where route.stateId != state.currentStateId {
            guard isEligible(route), route.info.priority > best?.info.priority ?? Int.min
            else {
                continue
            }
            best = route
        }
        guard let best, stateInfo(of: machine, id: best.stateId) != nil else { return false }
        if let running = state.transition, running.refuses(best.info) {
            return false
        }
        var effect = (best.holder?.stateMachines ?? self).effect(for: best.info)
        effect?.priority = best.info.priority
        effect?.interrupted = state.transition.map { [$0] } ?? []
        effect?.trim(to: machine.maxSimultaneousTransitions)
        switchState(&state, to: best.stateId, machine: machine, transition: effect)
        graph.pendingNestedStateIds = best.nestedStateIds
        return true
    }

    private func isEligible(_ route: BehaviorGlobalWildcardRoute) -> Bool {
        guard let holder = route.holder else {
            return graph.events.isActive(id: route.info.eventId) && permits(route)
        }
        // Event ids differ per file, so the event is matched by name.
        let names = holder.events.names
        guard
            names.indices.contains(route.info.eventId), let name = names[route.info.eventId],
            let id = graph.events.index(of: name), graph.events.isActive(id: id)
        else { return false }
        return holder.stateMachines.permits(route)
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
                    route.holder = $0.holder ?? child
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
