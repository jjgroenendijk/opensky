// Records each assembled actor into the cell build.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellActorRecorder {
    /// Buckets one assembled actor: drawn plus its animation outcome, or a
    /// counted failure with its reason. Split out of `resolveActors` so both
    /// stay inside the strict-lint function-body cap.
    nonisolated func record(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        id: String,
        into build: inout CellActorBuild
    ) {
        build.counts.appearanceSkipReasons += Self.appearanceSkipLines(assembly, id: id)
        guard assembly.isRenderable else {
            build.counts.failures += 1
            let reasons = assembly.skips.map { String(describing: $0.reason) }
                .joined(separator: ", ")
            build.counts.failureReasons.append(
                "ACHR \(id): no renderable geometry (\(reasons))"
            )
            CellSceneBuilder.logger.warning(
                """
                ACHR \(id, privacy: .public): no renderable geometry \
                (\(reasons, privacy: .public)), failed
                """
            )
            return
        }
        build.counts.rendered += 1
        let faceMorph = owner.actorBuilder.morphs.makeFaceMorphPlayback(assembly: assembly)
        build.placements.append(contentsOf: assembly.renderPlacements(
            at: assembly.transform,
            faceMorphs: faceMorph?.renderBuffers ?? [:],
            owner: assembly.actor.rawValue,
            reference: assembly.actor.rawValue
        ))
        var skeleton: ActorAnimationPlayback?
        switch owner.actorBuilder.animation.makeAnimationPlayback(assembly: assembly) {
        case let .success(playback):
            build.counts.animated += 1
            skeleton = playback
        case let .failure(error):
            build.counts.animationFailures += 1
            build.counts.animationFailureReasons.append(
                "ACHR \(id): \(error.localizedDescription)"
            )
        }
        if let faceMorph {
            build.animations.append(faceMorph)
            build.animations.append(LipSyncPlayback(faceMorph: faceMorph, head: skeleton))
        }
        if let skeleton {
            build.animations.append(skeleton)
        }
    }

    /// A cut head: drawn at its actor, posed by its own playback so it can fall apart from
    /// the body. Its outcome is not counted, because the actor is already counted.
    nonisolated func recordSeveredHead(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        into build: inout CellActorBuild
    ) {
        guard
            assembly.isRenderable,
            case let .success(playback) = owner.actorBuilder.animation.makeAnimationPlayback(
                assembly: assembly, severedHead: true
            )
        else { return }
        build.placements.append(contentsOf: assembly.renderPlacements(
            at: assembly.transform,
            owner: assembly.actor.rawValue,
            reference: assembly.actor.rawValue,
            isCulled: false
        ))
        build.animations.append(playback)
    }

    /// The assembly's `AppearanceSkip` entries as readable lines, one per skip.
    ///
    /// Only the `.appearance` subject is taken: the other `ActorAssemblySkip`
    /// subjects are asset-loading outcomes, which the failure buckets above
    /// already own, and mixing the two would make a missing NIF read as a
    /// resolution decision.
    nonisolated private static func appearanceSkipLines(
        _ assembly: ActorAssembly<ActorRenderAsset>,
        id: String
    ) -> [String] {
        assembly.skips.compactMap { skip in
            guard case let .appearance(appearance) = skip.subject else { return nil }
            return "ACHR \(id): \(appearance.reason) (\(appearance.subject))"
        }
    }
}
