// A reference a script moves pushes the loose bodies in its `OBND` box, because its own
// collision is not a physics body (docs/engine/papyrus-translation.md).

import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension ScriptWorldAdapter {
    /// Draws each running move and lets it push the loose bodies in its way.
    func publishTranslations(
        _ poses: [ReferenceKey: ReferenceTransformOverride],
        moves: [ReferenceKey: PapyrusTranslation]
    ) {
        pushLooseBodies(by: moves)
        game.gameSession?.instancePoses.scriptedPoses = poses
            .reduce(into: [:]) { matrices, entry in
                guard let formID = game.streamer?.referenceEntry(key: entry.key)?.formID
                else { return }
                matrices[formID.rawValue] = MatrixMath.placement(
                    position: entry.value.position, rotation: entry.value.rotation, scale: 1
                )
            }
    }

    func pushLooseBodies(by translations: [ReferenceKey: PapyrusTranslation]) {
        guard
            let streamer = game.streamer, streamer.dynamicBodies.bodyCount > 0,
            let keywords = game.worldData?.locationStore?.keywords
        else { return }
        for key in translations.keys.sorted() {
            guard
                let move = translations[key], move.velocity != .zero,
                let base = streamer.referenceEntry(key: key)?.placedReference?.base,
                let id = keywords.resolvedID(base, fromPlugin: FormIDResolver.loadOrderSpaceName),
                let bounds = keywords.bounds(of: id), !bounds.isEmpty
            else { continue }
            let scale = streamer.referenceEntry(key: key)?.placedReference?.scale ?? 1
            streamer.dynamicBodies.push(by: ScriptedMover(
                placement: MatrixMath.placement(
                    position: move.position, rotation: move.rotation, scale: 1
                ),
                minimum: SIMD3<Float>(bounds.minimum) * scale,
                maximum: SIMD3<Float>(bounds.maximum) * scale,
                velocity: move.velocity
            ))
        }
    }
}
