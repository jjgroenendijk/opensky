// Entering a state starts its generator from the beginning. A state that is still
// blending out, or that the last update reached, keeps its node state otherwise, so a
// clip that already played to its end would stay there.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// Deactivates the incoming state's nodes, except those the outgoing state shares.
    /// The swinging blade trap needs this: its script raises `Single` again in the
    /// update after `Reset`, while the finished swing is still blending out.
    func restartGenerator(ofState stateId: Int, leaving currentId: Int, machine: HKBStateMachine) {
        guard
            stateId != currentId,
            let incoming = stateInfo(of: machine, id: stateId) else { return }
        var kept: Set<HKXPointerTarget> = []
        if let outgoing = stateInfo(of: machine, id: currentId)?.info.generator {
            collectSubtree(at: outgoing, depth: 0, into: &kept)
        }
        var restarted: Set<HKXPointerTarget> = []
        if let generator = incoming.info.generator {
            collectSubtree(at: generator, depth: 0, into: &restarted)
        }
        let stale = restarted.subtracting(kept).filter { nodeStates[$0] != nil }
        guard !stale.isEmpty else { return }
        deactivateNodes(stale)
    }

    private func collectSubtree(
        at target: HKXPointerTarget, depth: Int, into targets: inout Set<HKXPointerTarget>
    ) {
        guard
            depth < Self.maximumDepth, targets.insert(target).inserted,
            let node = compiledNode(at: target) else { return }
        for child in node.children {
            collectSubtree(at: child, depth: depth + 1, into: &targets)
        }
    }
}
