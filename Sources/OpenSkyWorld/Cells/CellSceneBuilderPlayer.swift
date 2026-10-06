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

/// What a scene provider has to answer for the app to draw a player.
nonisolated public protocol PlayerBodyProviding {
    /// The mounted archives, for loading the behavior graph and its clips.
    var playerAssetFileSystem: (any GameFileSource)? { get }

    /// Assembles the body and binds it to `pose`, the buffer the locomotion
    /// bridge publishes graph poses into.
    func makePlayerBody(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) -> Result<PlayerBody, PlayerBodyError>

    /// Assembles the first-person arms from the same equipped set, over the
    /// first-person rig and the first-person graph's pose.
    func makePlayerFirstPersonRig(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) -> Result<PlayerFirstPersonRig, PlayerBodyError>
}

nonisolated extension CellSceneBuilder: PlayerBodyProviding {
    public var playerAssetFileSystem: (any GameFileSource)? {
        fileSystem
    }

    public func makePlayerBody(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) -> Result<PlayerBody, PlayerBodyError> {
        assemblePlayer(
            equipped: equipped, appearance: appearance, firstPerson: false, label: "player body"
        )
        .map { assembly in
            PlayerBody(
                assembly: assembly,
                animation: PlayerAnimationPlayback(
                    skeleton: skeleton,
                    pose: pose,
                    models: assembly.models.map(\.asset.model)
                ),
                faceMorphs: appearance
                    .map { chargenMorphs(assembly: assembly, appearance: $0) } ?? [:]
            )
        }
    }

    public func makePlayerFirstPersonRig(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) -> Result<PlayerFirstPersonRig, PlayerBodyError> {
        assemblePlayer(
            equipped: equipped, appearance: appearance, firstPerson: true, label: "player arms"
        )
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
