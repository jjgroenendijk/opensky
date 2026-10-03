// The Idles section's controls over the idle coordinator.

import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator: IdleControlProviding {
    public func idleSnapshot(for actor: ReferenceKey?) -> IdleControlSnapshot {
        guard let store, world?.idleReferencePlacements() != nil else { return .unavailable }
        let holders = Dictionary(
            sessions.compactMap { key, session in session.marker.map { ($0.reference, key) } },
            uniquingKeysWith: min
        )
        return IdleControlSnapshot(
            isAvailable: true,
            usesIdleMarkers: usesIdleMarkers,
            markers: markers.map { placement in
                let idles = store.idles(of: placement.marker)
                let record = placement.marker.record
                return IdleMarkerReadout(
                    reference: placement.reference,
                    editorID: record.editorID ?? placement.marker.id.description,
                    idles: idles.map { $0.record.editorID ?? $0.id.description },
                    idleIDs: idles.map(\.id),
                    inSequence: IdleCore.selectionOrder(of: record) == .sequence,
                    doOnce: IdleCore.isDoOnce(record),
                    timer: record.idleTimer ?? 0,
                    claimedBy: holders[placement.reference]
                )
            },
            idlingActorCount: sessions.values.count { $0.arrived },
            report: actor.flatMap { reports[$0] }
        )
    }

    public func setUsesIdleMarkers(_ enabled: Bool) {
        usesIdleMarkers = enabled
    }

    public func idleTree(below idle: ResolvedFormID) -> [IdleTreeLine] {
        guard let store else { return [] }
        var lines: [IdleTreeLine] = []
        var visited: Set<ResolvedFormID> = []
        func visit(_ id: ResolvedFormID, depth: Int) {
            guard visited.insert(id).inserted, let record = store.idles.record(id) else { return }
            lines.append(IdleTreeLine(
                editorID: record.record.editorID ?? id.description,
                depth: depth,
                event: record.record.animationEvent
            ))
            store.forest.children(of: id).forEach { visit($0, depth: depth + 1) }
        }
        visit(idle, depth: 0)
        return lines
    }

    @discardableResult
    public func fireIdle(
        _ idle: ResolvedFormID,
        on actor: ReferenceKey,
        ignoringConditions: Bool
    ) -> IdleReport? {
        guard let store, let record = store.idles.record(idle) else { return nil }
        guard let now = world?.idleAnimationTime else {
            return failed(actor, source: "fired", "no renderer")
        }
        var selection = selector(for: actor).select(roots: [record])
        if ignoringConditions, selection.chosen == nil {
            selection = IdleSelection(chosen: record, trace: selection.trace, chosenEntry: nil)
        }
        return play(selection, on: actor, source: "fired", now: now)
    }

    @discardableResult
    public func pickIdle(at marker: ReferenceKey, for actor: ReferenceKey) -> IdleReport? {
        guard
            let placement = markers.first(where: { $0.reference == marker }),
            let now = world?.idleAnimationTime
        else { return nil }
        return select(at: placement, for: actor, now: now)
    }
}
