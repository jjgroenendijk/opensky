// Loads one animation clip for one character skeleton. Paths come from the behavior
// census of this install, never memory. Idle clips are gendered
// (`animations\male\mt_idle.hkx`), combat clips are not. A creature keeps its clips
// beside its own skeleton, without the `mt_` prefix. There is no unarmed stagger,
// so `1hm_` small stagger stands in; the same rig binds it.
// See docs/engine/combat-behavior.md and docs/engine/actor-animation.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsAnimation
import OpenSkyPhysics

nonisolated public enum ActorAnimationClipLoader: Sendable {
    /// Where every character animation and skeleton lives.
    public static let characterRoot = "meshes\\actors\\character\\"

    /// The gendered idle locomotion clip, which is what an NPC plays when
    /// nothing has asked for anything else.
    public static func idleAnimationPath(female: Bool) -> String {
        characterRoot + "animations\\\(female ? "female" : "male")\\mt_idle.hkx"
    }

    /// The idle clip of the skeleton at `skeletonMeshPath`: gendered for a character,
    /// `animations\idle.hkx` beside a creature's skeleton.
    public static func idleAnimationPath(skeletonMeshPath: String, female: Bool) -> String {
        guard let root = creatureRoot(skeletonMeshPath) else {
            return idleAnimationPath(female: female)
        }
        return root + "animations\\idle.hkx"
    }

    /// Direct gait clips named by the vanilla behavior graph census. They are
    /// in-place; the NPC capsule remains the sole movement authority.
    public static func gaitAnimationPath(_ gait: LocomotionGait, female: Bool) -> String? {
        gaitFileName(gait).map {
            characterRoot + "animations\\\(female ? "female" : "male")\\mt_" + $0
        }
    }

    /// The gait clip for any skeleton, as `idleAnimationPath(skeletonMeshPath:female:)`.
    public static func gaitAnimationPath(
        _ gait: LocomotionGait, skeletonMeshPath: String, female: Bool
    ) -> String? {
        guard let root = creatureRoot(skeletonMeshPath) else {
            return gaitAnimationPath(gait, female: female)
        }
        return gaitFileName(gait).map { root + "animations\\" + $0 }
    }

    /// `meshes\actors\horse\` for `meshes\actors\horse\character assets\skeleton.nif`;
    /// nil for the character skeleton and for a path outside `meshes\actors\`.
    static func creatureRoot(_ skeletonMeshPath: String) -> String? {
        guard
            !skeletonMeshPath.hasPrefix(characterRoot),
            skeletonMeshPath.hasPrefix(actorsRoot),
            let assets = skeletonMeshPath.range(of: "\\character assets\\")
        else { return nil }
        return String(skeletonMeshPath[..<assets.lowerBound]) + "\\"
    }

    private static let actorsRoot = "meshes\\actors\\"

    private static func gaitFileName(_ gait: LocomotionGait) -> String? {
        switch gait {
        case .walk: "walkforward.hkx"
        case .run, .sprint: "runforward.hkx"
        case .sneak, .swim: nil
        }
    }

    /// The clip one combat reaction plays, as a canonical VFS path.
    public static func animationPath(for clip: CombatActorClip) -> String {
        characterRoot + "animations\\" + fileName(for: clip)
    }

    /// How long a reaction clip holds the actor before idle. Ours, taken from the matching
    /// phase in `CombatBehaviorSettings.standard`, so clip and hit line up. Fixed, because
    /// a clip is decoded once per skeleton and shared.
    public static func holdSeconds(for clip: CombatActorClip) -> Float {
        let combat = CombatBehaviorSettings.standard
        switch clip {
        case .attack: return combat.windupSeconds + combat.recoverySeconds
        case .stagger: return combat.staggerSeconds
        case .hitReaction: return 0.4
        }
    }

    private static func fileName(for clip: CombatActorClip) -> String {
        switch clip {
        case .attack: "h2h_attackright.hkx"
        case .stagger: "1hm_staggerbacksmall.hkx"
        case .hitReaction: "h2h_recoilright.hkx"
        }
    }

    /// Decodes one clip: the rig `.hkx` beside `skeletonMeshPath`, the animation at
    /// `animationPath`, and their binding. `readHKX` is injected, so the cell builder and
    /// combat wiring each supply their own reader.
    public static func clip(
        skeletonMeshPath: String,
        animationPath: String,
        readHKX: (String) throws -> HKXFile
    ) throws -> ActorAnimationClip {
        guard
            skeletonMeshPath.hasPrefix(characterRoot) || creatureRoot(skeletonMeshPath) != nil,
            skeletonMeshPath.hasSuffix(".nif")
        else {
            throw ActorAnimationLoadError.unsupportedSkeleton(skeletonMeshPath)
        }
        let skeletonPath = String(skeletonMeshPath.dropLast(4)) + ".hkx"
        let skeletonFile = try readHKX(skeletonPath)
        let animationFile = try readHKX(animationPath)

        let bindings = try HKAAnimationBinding.bindings(in: animationFile)
        guard let binding = bindings.first else {
            throw ActorAnimationLoadError.noBinding(animationPath)
        }
        let animation = try animation(in: animationFile, binding: binding, path: animationPath)
        let skeletons = try HKASkeleton.skeletons(in: skeletonFile)
        let skeleton = skeletons.first {
            binding.originalSkeletonName == nil || $0.name == binding.originalSkeletonName
        } ?? skeletons.first
        guard let skeleton else {
            throw ActorAnimationLoadError.noRig(skeletonPath)
        }
        _ = try binding.boneIndices(transformTrackCount: animation.transformTrackCount)
        return ActorAnimationClip(
            skeleton: skeleton,
            animation: animation,
            binding: binding,
            skeletonMeshPath: skeletonMeshPath
        )
    }

    /// The animation the binding points at, falling back to the file's first
    /// when the pointer resolves to nothing.
    private static func animation(
        in file: HKXFile,
        binding: HKAAnimationBinding,
        path: String
    ) throws -> HKASplineCompressedAnimation {
        let animations = try HKASplineCompressedAnimation.animations(in: file)
        let matched = animations.first { candidate in
            binding.animationTarget == HKXPointerTarget(
                sectionIndex: candidate.objectSectionIndex,
                dataOffset: candidate.objectDataOffset
            )
        } ?? animations.first
        guard let matched else {
            throw ActorAnimationLoadError.noClip(path)
        }
        return matched
    }
}
