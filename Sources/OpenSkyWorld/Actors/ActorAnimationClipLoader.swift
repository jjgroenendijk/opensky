// Loads one animation clip for one character skeleton. Paths come from the behavior
// census of this install, never memory. Idle clips are gendered
// (`animations\male\mt_idle.hkx`), combat clips are not. There is no unarmed stagger,
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

    /// Direct gait clips named by the vanilla behavior graph census. They are
    /// in-place; the NPC capsule remains the sole movement authority.
    public static func gaitAnimationPath(_ gait: LocomotionGait, female: Bool) -> String? {
        let fileName: String
        switch gait {
        case .walk:
            fileName = "mt_walkforward.hkx"
        case .run, .sprint:
            fileName = "mt_runforward.hkx"
        case .sneak, .swim:
            return nil
        }
        return characterRoot + "animations\\\(female ? "female" : "male")\\" + fileName
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
            skeletonMeshPath.hasPrefix(characterRoot),
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
