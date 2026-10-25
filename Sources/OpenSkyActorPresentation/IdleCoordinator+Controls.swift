// The Idles section's controls over the idle coordinator.

import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator {
    public func idleSnapshot(for actor: ReferenceKey?) -> IdleControlSnapshot {
        guard let store, world?.idleReferencePlacements() != nil else { return .unavailable }
        let holders = Dictionary(
            sessions.compactMap { key, session in session.marker.map { ($0.reference, key) } },
            uniquingKeysWith: min
        )
        return IdleControlSnapshot(
            isAvailable: true,
            markers: markers.map { placement in
                let idles = store.idles(of: placement.marker)
                let record = placement.marker.record
                return IdleMarkerReadout(
                    editorID: record.editorID ?? placement.marker.id.description,
                    idles: idles.map { $0.record.editorID ?? $0.id.description },
                    claimedBy: holders[placement.reference]
                )
            },
            idlingActorCount: sessions.values.count { $0.arrived },
            report: actor.flatMap { reports[$0] }
        )
    }

    /// True while `actor` has claimed an idle marker, walking to it or playing there.
    public func holdsMarker(_ actor: ReferenceKey) -> Bool {
        sessions[actor]?.marker != nil
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
        let report = play(selection, on: actor, source: "fired", now: now)
        // A dependent takes the same event from wherever its own graph is.
        guard let chosen = selection.chosen else { return report }
        for dependent in withDependents(actor).dropFirst() {
            play(
                IdleSelection(chosen: chosen, trace: [], chosenEntry: nil),
                on: dependent, source: "dependent", now: now
            )
        }
        return report
    }
}
