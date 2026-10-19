// Assembles the player body with the same resolvers a streamed NPC uses, so
// slot masking, FaceGen, and equipment work without a second path. Two things
// differ: the base record is named directly, and the transform comes from the
// character controller. It builds no cell, and its result outlives scene swaps.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import simd

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
        let resolvers = actorResolversBuildingIfNeeded()
        let override = override.map(withSkinTone)
        let assembly: ActorAssembly<ActorRenderAsset>
        do {
            var appearance = try resolvers.template.resolve(base: PlayerBody.baseFormID)
            if let override {
                appearance = appearance.applying(override)
            }
            var visual = try resolvers.visual.resolve(appearance: appearance, equipped: equipped)
            // The install bakes no FaceGen head for the player base, so the
            // player's head is always built from its head parts.
            visual.headSource = .assembled
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

    /// The face takes the race's default skin tone when it has no layer of its own,
    /// and the body takes the colour of that layer.
    private func withSkinTone(_ override: PlayerAppearanceOverride) -> PlayerAppearanceOverride {
        var override = override
        let masks = raceTintMasks(override)
        override.addDefaultSkinTone(masks: masks) { [actorVisualResolver] id in
            actorVisualResolver?.colors[id.rawValue]?.color
        }
        override.skinTone = override.skinToneLayerColour(masks: masks)
        return override
    }
}
