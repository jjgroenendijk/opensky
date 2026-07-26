// Ambience-context emission (M9.2.2): builds an `AmbienceContext` value from
// the streamer's current state and fires `onAmbienceContextChanged` when it
// differs from the previous emission. Split from CellStreamer.swift for the
// same file-size reason as CellStreamerTransitions.
//
// Sources of context:
//   - Interior enter/exit: `apply(transition:)` clears/sets `interiorScene`.
//   - Exterior recenter: the per-frame `update()` walk in CellStreamer.swift.
// Both call `emitAmbienceContextIfNeeded()` here.

import Foundation

/// Cheap identity for diff: only the fields that drive `AmbienceBed.resolve`.
/// The director's bed cache means equal keys never re-resolve.
nonisolated struct AmbienceKey: Equatable, Sendable {
    let isInterior: Bool
    let interiorFormID: UInt32?
    let exteriorCenter: CellCoordinate?
    let regions: [UInt32]
    let acousticSpace: UInt32?
}

extension CellStreamer {
    /// Resolves the streamer's current center cell into an ambience key, and
    /// emits a fresh `AmbienceContext` when it differs from the previous one.
    /// Called from update() and apply(transition:).
    func emitAmbienceContextIfNeeded() {
        let key = currentAmbienceKey()
        guard key != lastEmittedAmbienceKey else { return }
        lastEmittedAmbienceKey = key
        onAmbienceContextChanged?(currentAmbienceContext(key: key))
    }

    /// Forces a re-emit on the next call. Used after a transition that swaps
    /// scenes without changing the key (e.g. an interior re-entered with the
    /// same FormID and a fresh ASPC resolution).
    func invalidateAmbienceContext() {
        lastEmittedAmbienceKey = nil
    }

    private func currentAmbienceKey() -> AmbienceKey {
        if let interiorScene {
            return AmbienceKey(
                isInterior: true,
                interiorFormID: interiorCellFormID(in: interiorScene),
                exteriorCenter: nil,
                regions: [],
                acousticSpace: interiorScene.acousticSpace?.rawValue
            )
        }
        let center = grid.center
        let scene = composition.cells[center]
        return AmbienceKey(
            isInterior: false,
            interiorFormID: nil,
            exteriorCenter: center,
            regions: scene?.regions.map(\.rawValue) ?? [],
            acousticSpace: nil
        )
    }

    private func currentAmbienceContext(key: AmbienceKey) -> AmbienceContext {
        if key.isInterior {
            return AmbienceContext(
                regions: [],
                acousticSpace: key.acousticSpace.map { FormID($0) },
                isInterior: true
            )
        }
        let regions = (composition.cells[grid.center]?.regions) ?? []
        return AmbienceContext(
            regions: regions,
            acousticSpace: nil,
            isInterior: false
        )
    }

    private func interiorCellFormID(in scene: CellScene) -> UInt32? {
        guard case let .interior(formID) = scene.location else { return nil }
        return formID.rawValue
    }
}
