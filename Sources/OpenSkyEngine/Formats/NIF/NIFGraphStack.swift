// Explicit work stack shared by every NIF graph walk.
//
// A NIF is attacker-shaped input: a mod-supplied mesh nests its blocks as
// deeply as the file format allows. Descending one call frame per level makes
// the parser's real limit the thread's stack rather than the depth cap it
// advertises, and the margin between the two is thin. One frame carries a
// decoded node and a float4x4, the block decoder sits on top of it, and a
// secondary thread runs on the 512 KB default rather than the main thread's
// 8 MB — so a file the cap was supposed to reject can hit the guard page
// first. Under Address Sanitizer, whose redzones widen every frame, it
// reliably did (issue #388).
//
// Holding pending work here spends heap instead, which turns each walk's depth
// cap back into a plausibility policy on scene graphs rather than a proxy for a
// stack budget. Callers keep their own range, depth, and cycle diagnostics;
// this type only owns the traversal order and the root-to-node path.

import Foundation
import simd

/// Depth-first traversal state for a NIF block graph, ordered so that
/// `next()` yields the same sequence a recursive pre-order walk would.
nonisolated struct NIFGraphStack {
    /// One block reference waiting to be visited, with the world transform
    /// accumulated down its parent chain and its distance from the root.
    struct Pending {
        let ref: Int32
        let parent: float4x4
        let depth: Int
    }

    private enum Step {
        case enter(Pending)
        /// Sentinel queued behind a node's children: popping it means the
        /// subtree finished, so the node leaves the current path.
        case leave(index: Int)
    }

    private var steps: [Step]
    /// Blocks on the current root-to-node path, for cycle detection. A set,
    /// not a visited list: legitimate graphs reuse a subtree under two parents.
    private var path: Set<Int> = []

    init(root: Int32, parent: float4x4 = matrix_identity_float4x4) {
        steps = [.enter(Pending(ref: root, parent: parent, depth: 0))]
    }

    /// The next reference to visit, unwinding any subtrees that just finished.
    /// `nil` once the walk is complete.
    mutating func next() -> Pending? {
        while let step = steps.popLast() {
            switch step {
            case let .leave(index):
                path.remove(index)
            case let .enter(pending):
                return pending
            }
        }
        return nil
    }

    /// Puts `index` on the current path and arranges for it to come back off
    /// once its subtree finishes. `false` means the block is already on the
    /// path, which is a cycle; the caller decides whether that throws.
    mutating func enter(_ index: Int) -> Bool {
        guard path.insert(index).inserted else { return false }
        steps.append(.leave(index: index))
        return true
    }

    /// Queues `children` under the node just entered so they come back from
    /// `next()` in the order they appear in the block.
    mutating func push(children: [Int32], parent: float4x4, depth: Int) {
        for child in children.reversed() {
            steps.append(.enter(Pending(ref: child, parent: parent, depth: depth)))
        }
    }
}
