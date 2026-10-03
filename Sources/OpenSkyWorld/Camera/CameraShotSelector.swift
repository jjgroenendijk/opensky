// Picks a cinematic camera shot by walking the CPTH path tree for one attacker
// and one target. The walk rule and where it comes from:
// docs/formats/camera-records.md#shot-selection.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// One path the selector looked at, and what happened to it.
nonisolated public struct CameraPathTrace: Equatable, Sendable {
    nonisolated public enum Verdict: Equatable, Sendable {
        /// Its shots are the candidates.
        case chosen
        /// Its conditions passed and a child below it was chosen.
        case passed
        /// The Creation Kit name of the first condition that failed.
        case rejected(String)
        /// The walk stopped before it, or its parent failed.
        case notReached
        /// Its conditions passed, but it has no shots and no child has any.
        case noShots
    }

    public let id: ResolvedFormID
    public let editorID: String?
    public let depth: Int
    public let verdict: Verdict
}

nonisolated public struct CameraShotSelection: Sendable {
    /// The path whose shots were the candidates, or nil when no path passed.
    public let path: ResolvedRecord<CameraPath>?
    public let candidates: [ResolvedRecord<CameraShot>]
    /// One seeded pick per stage, in CAMS action order: shoot, fly, hit.
    public let sequence: [ResolvedRecord<CameraShot>]
    public let trace: [CameraPathTrace]

    /// The first shot to play.
    public var chosen: ResolvedRecord<CameraShot>? {
        sequence.first
    }

    public static let none = CameraShotSelection(path: nil, candidates: [], sequence: [], trace: [])
}

nonisolated public struct CameraShotSelector {
    public typealias Children = (ResolvedFormID) -> [ResolvedRecord<CameraPath>]
    public typealias Shots = (ResolvedRecord<CameraPath>) -> [ResolvedRecord<CameraShot>]
    /// The failing condition's name, or nil when the conditions pass.
    public typealias Check = (CameraPath) -> String?

    private let roots: [ResolvedRecord<CameraPath>]
    private let children: Children
    private let shots: Shots
    private let check: Check

    public init(
        roots: [ResolvedRecord<CameraPath>],
        children: @escaping Children,
        shots: @escaping Shots,
        check: @escaping Check
    ) {
        self.roots = roots
        self.children = children
        self.shots = shots
        self.check = check
    }

    public init(store: CameraPathStore, check: @escaping Check) {
        self.init(
            roots: store.forest.roots.compactMap { store.paths.record($0) },
            children: { id in store.forest.children(of: id).compactMap { store.paths.record($0) } },
            shots: { store.shots(of: $0) },
            check: check
        )
    }

    /// Walks every root in sibling order; the first one that yields shots wins.
    /// `random` gets a stage's shot count and returns an index below it.
    public func select(random: (Int) -> Int) -> CameraShotSelection {
        var traces: [CameraPathTrace] = []
        for (index, root) in roots.enumerated() {
            let walk = walk(root, depth: 0)
            traces += walk.trace
            guard let path = walk.chosen else { continue }
            traces += roots.dropFirst(index + 1).flatMap { notReached($0, depth: 0) }
            let candidates = shots(path)
            return CameraShotSelection(
                path: path,
                candidates: candidates,
                sequence: Self.stages(of: candidates).map { stage in
                    stage[min(max(random(stage.count), 0), stage.count - 1)]
                },
                trace: traces
            )
        }
        return CameraShotSelection(path: nil, candidates: [], sequence: [], trace: traces)
    }

    /// The path's shots grouped by CAMS action, lowest action first. A shot
    /// with no DATA plays as the first stage.
    public static func stages(of shots: [ResolvedRecord<CameraShot>])
        -> [[ResolvedRecord<CameraShot>]]
    {
        Dictionary(grouping: shots) { $0.record.properties?.action ?? 0 }
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    /// A seeded pick through `ConditionRandom`, so a test repeats.
    public func select(random generator: inout ConditionRandom) -> CameraShotSelection {
        select { count in count > 0 ? Int(generator.next() % UInt64(count)) : 0 }
    }

    private struct Walk {
        let chosen: ResolvedRecord<CameraPath>?
        let trace: [CameraPathTrace]
    }

    /// A passing path hands over to its first child that yields shots, and
    /// offers its own shots only when no child does.
    private func walk(_ node: ResolvedRecord<CameraPath>, depth: Int) -> Walk {
        let below = children(node.id)
        let skipped = below.flatMap { notReached($0, depth: depth + 1) }
        if let failure = check(node.record) {
            return Walk(chosen: nil, trace: [trace(node, depth, .rejected(failure))] + skipped)
        }
        var childTraces: [CameraPathTrace] = []
        for (index, child) in below.enumerated() {
            let result = walk(child, depth: depth + 1)
            childTraces += result.trace
            if let chosen = result.chosen {
                childTraces += below.dropFirst(index + 1)
                    .flatMap { notReached($0, depth: depth + 1) }
                return Walk(chosen: chosen, trace: [trace(node, depth, .passed)] + childTraces)
            }
        }
        guard !shots(node).isEmpty else {
            return Walk(chosen: nil, trace: [trace(node, depth, .noShots)] + childTraces)
        }
        return Walk(chosen: node, trace: [trace(node, depth, .chosen)] + childTraces)
    }

    private func notReached(_ node: ResolvedRecord<CameraPath>, depth: Int) -> [CameraPathTrace] {
        [trace(node, depth, .notReached)]
            + children(node.id).flatMap { notReached($0, depth: depth + 1) }
    }

    private func trace(
        _ node: ResolvedRecord<CameraPath>,
        _ depth: Int,
        _ verdict: CameraPathTrace.Verdict
    ) -> CameraPathTrace {
        CameraPathTrace(id: node.id, editorID: node.record.editorID, depth: depth, verdict: verdict)
    }
}

nonisolated extension CameraShotSelector {
    /// The standard check: each path's conditions run on the attacker, with the
    /// target as the Target run-on.
    public static func conditionCheck(
        context base: ConditionContext,
        attacker: ReferenceKey,
        target: ReferenceKey?
    ) -> Check {
        var context = base
        context.subject = attacker
        context.target = target
        let prepared = context
        return { path in
            var evaluator = ConditionEvaluator(context: prepared)
            return evaluator.firstFailure(in: path.conditions).map(evaluator.functionName(of:))
        }
    }
}
