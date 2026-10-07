// Assembles the player body with the same resolvers a streamed NPC uses, so
// slot masking, FaceGen, and equipment work without a second path. Two things
// differ: the base record is named directly, and the transform comes from the
// character controller. It builds no cell, and its result outlives scene swaps.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import simd

/// Why the player has no body. Every case is reported rather than swallowed:
/// a bodiless player in third person looks like a rendering bug, and the panel
/// has to be able to say which of these it actually is.
nonisolated public enum PlayerBodyError: LocalizedError, Equatable {
    case noFileSystem
    case unresolvedBase(FormID, String)
    case noRenderableGeometry([String])
    case behavior(PlayerBehaviorGraphError)

    public var errorDescription: String? {
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

nonisolated extension CellSceneBuilder {
    /// Runs on the build queue; the main actor binds the result to the live pose.
    public func assemblePlayerRig(
        _ request: PlayerRigRequest
    ) -> Result<PlayerRigAssembly, PlayerBodyError> {
        assemblePlayer(
            equipped: request.equipped,
            appearance: request.appearance,
            firstPerson: request.firstPerson,
            label: request.firstPerson ? "player arms" : "player body"
        )
        .map { assembly in
            let morphs = request.firstPerson ? nil : request.appearance
            return PlayerRigAssembly(
                assembly: assembly,
                faceMorphs: morphs.map { chargenMorphs(assembly: assembly, appearance: $0) } ?? [:]
            )
        }
    }

    public func makePlayerBody(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) -> Result<PlayerBody, PlayerBodyError> {
        let request = PlayerRigRequest(
            generation: 0, firstPerson: false, equipped: equipped, appearance: appearance
        )
        return assemblePlayerRig(request).map {
            PlayerBody(rig: $0, skeleton: skeleton, pose: pose)
        }
    }

    public func makePlayerFirstPersonRig(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) -> Result<PlayerFirstPersonRig, PlayerBodyError> {
        let request = PlayerRigRequest(
            generation: 0, firstPerson: true, equipped: equipped, appearance: appearance
        )
        return assemblePlayerRig(request).map {
            PlayerFirstPersonRig(rig: $0, skeleton: skeleton, pose: pose)
        }
    }

    /// Resolves the player's appearance once and assembles both rigs. The arms are the
    /// third-person answer through `firstPersonProjection`, so the rigs cannot disagree.
    private func assemblePlayer(
        equipped: [FormID]?,
        appearance override: PlayerAppearanceOverride?,
        firstPerson: Bool,
        label: String
    ) -> Result<ActorAssembly<ActorRenderAsset>, PlayerBodyError> {
        let resolvers = actorResolversBuildingIfNeeded(localized: pluginLocalized)
        let assembly: ActorAssembly<ActorRenderAsset>
        do {
            var appearance = try resolvers.template.resolve(base: PlayerBody.baseFormID)
            if let override {
                appearance = appearance.applying(override)
            }
            var visual = try resolvers.visual.resolve(appearance: appearance, equipped: equipped)
            if let override, !firstPerson {
                visual = chargenVisual(visual, appearance: override)
            }
            if firstPerson {
                visual = visual.firstPersonProjection(
                    skeletonPath: PlayerBehaviorGraph.firstPersonRigPath
                )
            }
            assembly = ActorAssembler(provider: meshes).assemble(
                actor: PlayerBody.actorFormID,
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
