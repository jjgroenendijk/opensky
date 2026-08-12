// Assembling the player body out of the same machinery a streamed NPC uses
// (issue #189).
//
// Item 14.6's rule is that the player is not a special case below the
// transform: it resolves through `ActorTemplateResolver` and
// `ActorVisualResolver` like any ACHR, so slot masking, FaceGen, and the M12
// equipment attachment path apply to it without a second implementation. The
// two things that differ are stated here and nowhere else: the base record is
// named directly (the player has no ACHR to read it from) and the transform
// comes from the character controller rather than from a record.
//
// This lives on `CellSceneBuilder` because that is where the resolvers, the
// `MeshLibrary`, and the archive file system already are. It builds no cell and
// touches no cell state: what it produces outlives every scene swap.

import Foundation
import OSLog
import simd

/// Why the player has no body. Every case is reported rather than swallowed:
/// a bodiless player in third person looks like a rendering bug, and the panel
/// has to be able to say which of these it actually is.
nonisolated enum PlayerBodyError: LocalizedError, Equatable {
    case noFileSystem
    case unresolvedBase(FormID, String)
    case noRenderableGeometry([String])
    case behavior(PlayerBehaviorGraphError)

    var errorDescription: String? {
        switch self {
        case .noFileSystem:
            "no game archives are mounted"
        case let .unresolvedBase(base, reason):
            "player base \(base.description) did not resolve: \(reason)"
        case let .noRenderableGeometry(reasons):
            "player base resolved to no renderable geometry (\(reasons.joined(separator: ", ")))"
        case let .behavior(error):
            error.errorDescription ?? "behavior graph unavailable"
        }
    }
}

/// What a scene provider has to answer for the app to draw a player.
nonisolated protocol PlayerBodyProviding {
    /// The mounted archives, for loading the behavior graph and its clips.
    var playerAssetFileSystem: VirtualFileSystem? { get }

    /// Assembles the body and binds it to `pose`, the buffer the locomotion
    /// bridge publishes graph poses into.
    func makePlayerBody(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?
    ) -> Result<PlayerBody, PlayerBodyError>

    /// Assembles the first-person arms from the same equipped set, over the
    /// first-person rig and the first-person graph's pose (issue #190).
    func makePlayerFirstPersonRig(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?
    ) -> Result<PlayerFirstPersonRig, PlayerBodyError>
}

nonisolated extension CellSceneBuilder: PlayerBodyProviding {
    var playerAssetFileSystem: VirtualFileSystem? {
        fileSystem
    }

    func makePlayerBody(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?
    ) -> Result<PlayerBody, PlayerBodyError> {
        assemblePlayer(equipped: equipped, firstPerson: false, label: "player body")
            .map { assembly in
                PlayerBody(
                    assembly: assembly,
                    animation: PlayerAnimationPlayback(
                        skeleton: skeleton,
                        pose: pose,
                        models: assembly.models.map(\.asset.model)
                    )
                )
            }
    }

    func makePlayerFirstPersonRig(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?
    ) -> Result<PlayerFirstPersonRig, PlayerBodyError> {
        assemblePlayer(equipped: equipped, firstPerson: true, label: "player arms")
            .map { assembly in
                PlayerFirstPersonRig(
                    assembly: assembly,
                    animation: PlayerAnimationPlayback(
                        skeleton: skeleton,
                        pose: pose,
                        models: assembly.models.map(\.asset.model)
                    )
                )
            }
    }

    /// Resolves the player's appearance and assembles it, once for each rig.
    ///
    /// One resolve, two projections: the first-person arms are the
    /// third-person answer put through `firstPersonProjection`, so the equipped
    /// set, the slot mask, and the M12 attachment path cannot disagree between
    /// the two rigs (`ActorVisualResolutionFirstPerson.swift`).
    private func assemblePlayer(
        equipped: [FormID]?,
        firstPerson: Bool,
        label: String
    ) -> Result<ActorAssembly<ActorRenderAsset>, PlayerBodyError> {
        let resolvers = actorResolversBuildingIfNeeded(localized: pluginLocalized)
        let assembly: ActorAssembly<ActorRenderAsset>
        do {
            let appearance = try resolvers.template.resolve(base: PlayerBody.baseFormID)
            var visual = try resolvers.visual.resolve(appearance: appearance, equipped: equipped)
            if firstPerson {
                visual = visual.firstPersonProjection(
                    skeletonPath: PlayerBehaviorGraph.firstPersonRigPath
                )
            }
            assembly = ActorAssembler(provider: meshes).assemble(
                actor: PlayerBody.actorFormID,
                base: PlayerBody.baseFormID,
                // Identity: `place` supplies the live transform every frame,
                // and a stale one baked in here would place the first frame at
                // the world origin.
                transform: matrix_identity_float4x4,
                visual: visual
            )
        } catch {
            return .failure(.unresolvedBase(PlayerBody.baseFormID, String(describing: error)))
        }
        guard assembly.isRenderable else {
            return .failure(.noRenderableGeometry(
                assembly.skips.map { String(describing: $0.reason) }
            ))
        }
        for skip in assembly.skips {
            Self.logger.info(
                "\(label, privacy: .public) skip: \(String(describing: skip), privacy: .public)"
            )
        }
        return .success(assembly)
    }
}
