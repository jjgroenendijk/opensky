// Picks one ambient idle for an actor from a marker's IDLA list or from the
// related-idle tree, and records why every other candidate lost. The rules
// and their sources: docs/engine/idle-runtime.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum IdleSelectionOrder: Equatable, Sendable {
    /// Any passing candidate, picked at random.
    case random
    /// The first passing candidate at or after the marker's next index.
    case sequence
}

/// One candidate the selector looked at, and what happened to it.
nonisolated public struct IdleCandidateTrace: Equatable, Sendable {
    nonisolated public enum Verdict: Equatable, Sendable {
        case chosen
        /// Its conditions passed, but another candidate was chosen.
        case passed
        /// The Creation Kit name of the first condition that failed.
        case rejected(String)
        /// The selector stopped before it, or its parent failed.
        case notReached
        /// A do-once marker already played it.
        case alreadyPlayed
        /// Its conditions passed, but it sends no event and no child passed.
        case noAnimation
    }

    public let id: ResolvedFormID
    public let editorID: String?
    /// 0 for a marker entry or a root; 1 for its child, and so on.
    public let depth: Int
    public let verdict: Verdict
}

nonisolated public struct IdleSelection: Sendable {
    public let chosen: ResolvedRecord<IdleAnimation>?
    public let trace: [IdleCandidateTrace]
    /// Index of the marker entry that won, or nil for a tree or no choice.
    public let chosenEntry: Int?
}

nonisolated public struct IdleSelector {
    public typealias Children = (ResolvedFormID) -> [ResolvedRecord<IdleAnimation>]
    /// The failing condition's name, or nil when the conditions pass.
    public typealias Check = (IdleAnimation) -> String?

    private let children: Children
    private let check: Check

    public init(children: @escaping Children, check: @escaping Check) {
        self.children = children
        self.check = check
    }

    public init(store: IdleStore, check: @escaping Check) {
        self.init(
            children: { id in store.forest.children(of: id).compactMap { store.idles.record($0) } },
            check: check
        )
    }

    /// A marker's IDLA list. `random` gets the passing count and returns an
    /// index below it, so a test can pin the choice.
    public func select(
        entries: [ResolvedRecord<IdleAnimation>],
        order: IdleSelectionOrder,
        startIndex: Int,
        played: Set<ResolvedFormID>,
        random: (Int) -> Int
    ) -> IdleSelection {
        let start = entries.isEmpty ? 0 : ((startIndex % entries.count) + entries.count)
            % entries.count
        let visitOrder = order == .sequence
            ? Array(start ..< entries.count) + Array(0 ..< start)
            : Array(entries.indices)
        var results: [Int: Walk] = [:]
        for index in visitOrder {
            let entry = entries[index]
            if played.contains(entry.id) {
                results[index] = Walk(chosen: nil, trace: [trace(entry, 0, .alreadyPlayed)])
                continue
            }
            let walk = walk(entry, depth: 0)
            results[index] = walk
            if order == .sequence, walk.chosen != nil {
                break
            }
        }
        let playable = visitOrder.filter { results[$0]?.chosen != nil }
        let winner: Int? = switch order {
        case .sequence: playable.first
        case .random: playable.isEmpty
            ? nil : playable[min(max(random(playable.count), 0), playable.count - 1)]
        }
        let traces = visitOrder.flatMap { index in
            guard let result = results[index] else {
                return notReached(entries[index], depth: 0)
            }
            return index == winner ? result.trace : demoted(result.trace)
        }
        return IdleSelection(
            chosen: winner.flatMap { results[$0]?.chosen },
            trace: traces,
            chosenEntry: winner
        )
    }

    /// The related-idle tree: the first passing root in sibling order, then the
    /// deepest passing child below it.
    public func select(roots: [ResolvedRecord<IdleAnimation>]) -> IdleSelection {
        var traces: [IdleCandidateTrace] = []
        for (index, root) in roots.enumerated() {
            let walk = walk(root, depth: 0)
            traces += walk.trace
            if let chosen = walk.chosen {
                traces += roots.dropFirst(index + 1).flatMap { notReached($0, depth: 0) }
                return IdleSelection(chosen: chosen, trace: traces, chosenEntry: nil)
            }
        }
        return IdleSelection(chosen: nil, trace: traces, chosenEntry: nil)
    }

    private struct Walk {
        let chosen: ResolvedRecord<IdleAnimation>?
        let trace: [IdleCandidateTrace]
    }

    /// A passing node hands over to its first playable child; it plays itself
    /// only when no child does.
    private func walk(_ node: ResolvedRecord<IdleAnimation>, depth: Int) -> Walk {
        let below = children(node.id)
        if let failure = check(node.record) {
            return Walk(
                chosen: nil,
                trace: [trace(node, depth, .rejected(failure))]
                    + below.flatMap { notReached($0, depth: depth + 1) }
            )
        }
        var childTraces: [IdleCandidateTrace] = []
        for (index, child) in below.enumerated() {
            let result = walk(child, depth: depth + 1)
            childTraces += result.trace
            if let chosen = result.chosen {
                childTraces += below.dropFirst(index + 1)
                    .flatMap { notReached($0, depth: depth + 1) }
                return Walk(chosen: chosen, trace: [trace(node, depth, .passed)] + childTraces)
            }
        }
        guard node.record.animationEvent?.isEmpty == false else {
            return Walk(chosen: nil, trace: [trace(node, depth, .noAnimation)] + childTraces)
        }
        return Walk(chosen: node, trace: [trace(node, depth, .chosen)] + childTraces)
    }

    private func notReached(
        _ node: ResolvedRecord<IdleAnimation>,
        depth: Int
    ) -> [IdleCandidateTrace] {
        [trace(node, depth, .notReached)]
            + children(node.id).flatMap { notReached($0, depth: depth + 1) }
    }

    private func demoted(_ traces: [IdleCandidateTrace]) -> [IdleCandidateTrace] {
        traces.map {
            $0.verdict == .chosen
                ? IdleCandidateTrace(
                    id: $0.id, editorID: $0.editorID, depth: $0.depth, verdict: .passed
                )
                : $0
        }
    }

    private func trace(
        _ node: ResolvedRecord<IdleAnimation>,
        _ depth: Int,
        _ verdict: IdleCandidateTrace.Verdict
    ) -> IdleCandidateTrace {
        IdleCandidateTrace(
            id: node.id, editorID: node.record.editorID, depth: depth, verdict: verdict
        )
    }
}
