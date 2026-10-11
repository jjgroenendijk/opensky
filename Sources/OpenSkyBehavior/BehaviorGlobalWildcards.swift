// Global wildcards (`FLAG_IS_GLOBAL_WILDCARD`): a wildcard of a nested machine
// that fires while that machine is not active. Each ancestor machine moves into
// the state that holds it, and the nested machines then start in the wildcard's
// target. Rule and evidence: docs/engine/behavior-state-machines.md.

import Foundation
import OpenSkyFormatsAnimation

/// A global wildcard as one ancestor machine sees it: which of its own states
/// to enter, then the start state of each machine below, outermost first.
nonisolated public struct BehaviorGlobalWildcardRoute: Sendable {
    public let stateId: Int
    public let nestedStateIds: [Int]
    public let owner: HKBStateMachine
    public let info: HKBStateMachineTransitionInfo
}

nonisolated extension BehaviorGraphInstance {
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
        if state.transition != nil {
            tally.note(.stateMachineTransitionInterrupted)
        }
        switchState(
            &state, to: best.stateId, machine: machine, transition: effect(for: best.info)
        )
        pendingNestedStateIds = best.nestedStateIds
        return true
    }

    private func isEligible(_ route: BehaviorGlobalWildcardRoute) -> Bool {
        let info = route.info
        guard info.flags & BehaviorTransitionFlag.disabled == 0 else { return false }
        guard events.isActive(id: info.eventId) else { return false }
        guard stateInfo(of: route.owner, id: info.toStateId) != nil else { return false }
        return isIntervalOpen(info) && isConditionMet(info)
    }

    // MARK: - Routes

    /// Every global wildcard below `machine`, built once per machine.
    func globalWildcardRoutes(
        of machine: HKBStateMachine,
        at target: HKXPointerTarget,
        depth: Int = 0
    ) -> [BehaviorGlobalWildcardRoute] {
        if let cached = globalWildcardRouteCache[target] {
            return cached
        }
        // Cached empty first, so a machine nested inside itself ends the walk.
        globalWildcardRouteCache[target] = []
        guard depth < Self.maximumDepth else { return [] }
        var routes: [BehaviorGlobalWildcardRoute] = []
        for case let stateTarget? in machine.states {
            guard let info = object(at: stateTarget, as: HKBStateMachineStateInfo.self) else {
                continue
            }
            for nested in machines(below: info.generator) {
                routes += ownGlobalWildcards(of: nested.machine).map {
                    route($0, from: info.stateId, owner: nested.machine)
                }
                routes += globalWildcardRoutes(
                    of: nested.machine, at: nested.target, depth: depth + 1
                ).map {
                    BehaviorGlobalWildcardRoute(
                        stateId: info.stateId,
                        nestedStateIds: [$0.stateId] + $0.nestedStateIds,
                        owner: $0.owner,
                        info: $0.info
                    )
                }
            }
        }
        globalWildcardRouteCache[target] = routes
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
            let array = object(at: target, as: HKBStateMachineTransitionInfoArray.self)
        else {
            return []
        }
        return array.transitions.filter {
            $0.flags & BehaviorTransitionFlag.globalWildcard != 0
        }
    }

    /// The first machines on each path down from `root`. The walk stops at a
    /// machine, because that machine's own routes cover what lies below it.
    private func machines(
        below root: HKXPointerTarget?
    ) -> [(machine: HKBStateMachine, target: HKXPointerTarget)] {
        var found: [(machine: HKBStateMachine, target: HKXPointerTarget)] = []
        var visited: Set<HKXPointerTarget> = []
        var stack = root.map { [$0] } ?? []
        while let target = stack.popLast() {
            guard visited.insert(target).inserted, let node = compiledNode(at: target) else {
                continue
            }
            if let machine = node.object as? HKBStateMachine {
                found.append((machine, target))
                continue
            }
            stack += node.children.reversed()
        }
        return found
    }
}
