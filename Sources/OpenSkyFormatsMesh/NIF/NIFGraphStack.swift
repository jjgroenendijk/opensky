// Explicit work stack for every NIF graph walk. A mod mesh can nest deeply,
// and one call frame per level could overflow a 512 KB secondary-thread stack
// before the depth cap rejects the file. A heap stack keeps the depth cap a
// data policy. Callers keep their own range, depth, and cycle checks.

import Foundation
import simd

/// Depth-first traversal state for a NIF block graph, ordered so that
/// `next()` yields the same sequence a recursive pre-order walk would.
nonisolated public struct NIFGraphStack: Sendable {
    /// One block reference waiting to be visited, with the world transform
    /// accumulated down its parent chain and its distance from the root.
    public struct Pending: Sendable {
        public let ref: Int32
        public let parent: float4x4
        public let depth: Int
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

    public init(root: Int32, parent: float4x4 = matrix_identity_float4x4) {
        steps = [.enter(Pending(ref: root, parent: parent, depth: 0))]
    }

    /// The next reference to visit, unwinding any subtrees that just finished.
    /// `nil` once the walk is complete.
    public mutating func next() -> Pending? {
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
    public mutating func enter(_ index: Int) -> Bool {
        guard path.insert(index).inserted else { return false }
        steps.append(.leave(index: index))
        return true
    }

    /// Queues `children` under the node just entered so they come back from
    /// `next()` in the order they appear in the block.
    public mutating func push(children: [Int32], parent: float4x4, depth: Int) {
        for child in children.reversed() {
            steps.append(.enter(Pending(ref: child, parent: parent, depth: depth)))
        }
    }
}
