// Music-context emission (M9.2.3): builds a `MusicContext` value from the
// streamer's current state and fires `onMusicContextChanged` when it differs
// from the previous emission. Mirrors CellStreamerAmbience exactly — same two
// call sites, same key-diff discipline, split into its own satellite for the
// same file-size reason.
//
// Sources of context:
//   - Interior enter/exit: `apply(transition:)` clears/sets `interiorScene`.
//   - Exterior recenter: the per-frame `update()` walk in CellStreamer.swift.

import Foundation

/// Cheap identity for diff: only the fields that drive `MusicSelection.resolve`.
/// Equal keys never re-resolve, so a steady-state frame costs one comparison.
nonisolated struct MusicKey: Equatable, Sendable {
    let isInterior: Bool
    let interiorFormID: UInt32?
    let exteriorCenter: CellCoordinate?
    let cellMusicType: UInt32?
    let regions: [UInt32]
    let worldspaceMusicType: UInt32?
}

extension CellStreamer {
    /// Resolves the streamer's current center cell into a music key, and emits
    /// a fresh `MusicContext` when it differs from the previous one. Called
    /// from update() and apply(transition:).
    func emitMusicContextIfNeeded() {
        let key = currentMusicKey()
        guard key != lastEmittedMusicKey else { return }
        lastEmittedMusicKey = key
        onMusicContextChanged?(Self.musicContext(key: key))
    }

    /// Forces a re-emit on the next call, for a scene swap that changes the
    /// music without changing the key (an interior re-entered with the same
    /// FormID after its playlist resolved differently).
    func invalidateMusicContext() {
        lastEmittedMusicKey = nil
    }

    private func currentMusicKey() -> MusicKey {
        if let interiorScene {
            return MusicKey(
                isInterior: true,
                interiorFormID: Self.interiorCellFormID(in: interiorScene),
                exteriorCenter: nil,
                cellMusicType: interiorScene.musicType?.rawValue,
                regions: [],
                worldspaceMusicType: nil
            )
        }
        let center = grid.center
        let scene = composition.cells[center]
        return MusicKey(
            isInterior: false,
            interiorFormID: nil,
            exteriorCenter: center,
            cellMusicType: scene?.musicType?.rawValue,
            regions: scene?.regions.map(\.rawValue) ?? [],
            worldspaceMusicType: scene?.worldspaceMusicType?.rawValue
        )
    }

    /// The key already carries every selection input, so the context is a pure
    /// re-shape of it — no second lookup that could disagree with the diff.
    private static func musicContext(key: MusicKey) -> MusicContext {
        MusicContext(
            isInterior: key.isInterior,
            cellMusicType: key.cellMusicType.map { FormID($0) },
            regions: key.regions.map { FormID($0) },
            worldspaceMusicType: key.worldspaceMusicType.map { FormID($0) },
            cellIdentity: key.interiorFormID ?? packed(key.exteriorCenter)
        )
    }

    /// Packs a grid coordinate into one identity word for the selection seed.
    private static func packed(_ coordinate: CellCoordinate?) -> UInt32 {
        guard let coordinate else { return 0 }
        return UInt32(bitPattern: coordinate.x) &* 0x0001_0001
            &+ UInt32(bitPattern: coordinate.y)
    }

    private static func interiorCellFormID(in scene: CellScene) -> UInt32? {
        guard case let .interior(formID) = scene.location else { return nil }
        return formID.rawValue
    }
}
