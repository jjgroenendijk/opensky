// Shared synthetic values for the trigger-volume runtime tests (issue #173):
// box volumes, cell scenes carrying them, and capsule poses. Every value is
// built in code; no game content is involved.

@testable import opensky
import simd

enum TriggerStreamFixture {
    /// Same plugin name `PapyrusWorldFixture` uses, so a volume's
    /// `ReferenceKey` matches the key a scripted reference entry gets.
    static let pluginName = PapyrusWorldFixture.pluginName

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName, objectID: objectID)
    }

    /// Axis-aligned box volume centred on `center`. Nil only for degenerate
    /// geometry, which none of these fixtures build.
    static func boxVolume(
        objectID: UInt32,
        center: SIMD3<Float>,
        halfExtents: SIMD3<Float> = SIMD3(repeating: 128)
    ) -> TriggerVolume? {
        TriggerVolume.placed(
            reference: key(objectID),
            formID: FormID(objectID),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: halfExtents)
        )
    }

    static func volumeSet(
        _ volumes: [TriggerVolume],
        location: CellSceneLocation? = nil
    ) -> TriggerVolumeSet {
        var stats = TriggerVolumeStats()
        stats.meshVolumeCount = volumes.count
        return TriggerVolumeSet(location: location, volumes: volumes, stats: stats)
    }

    /// Standard-capsule pose with its feet at `feet`.
    static func capsule(feetAt feet: SIMD3<Float>) -> PlayerCapsuleState {
        PlayerCapsuleState(capsule: .standard, feetPosition: feet)
    }

    /// Eye position the streamer is driven with for a given feet position.
    static func eye(feetAt feet: SIMD3<Float>) -> SIMD3<Float> {
        feet + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
    }

    /// Drives the streamer until every cell it asked for has been completed,
    /// so a multi-cell grid is fully resident before a test walks through it.
    @MainActor
    static func settle(
        streamer: CellStreamer,
        runner: ManualCellBuildRunner,
        eye position: SIMD3<Float>,
        sceneFor: (CellCoordinate) -> CellScene
    ) {
        var completed = 0
        for _ in 0 ..< 32 {
            streamer.update(cameraPosition: position)
            while completed < runner.enqueued.count {
                let coordinate = runner.enqueued[completed]
                completed += 1
                runner.complete(coordinate, with: .success(sceneFor(coordinate)))
            }
        }
    }
}
