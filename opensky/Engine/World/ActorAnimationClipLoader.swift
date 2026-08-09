// Loading one animation clip for one character skeleton (split out of
// `ActorAnimationPlayback.swift` for issue #374).
//
// The loader used to be a private method that hard-coded `mt_idle.hkx`, because
// an NPC played exactly one clip and that was it. The dev target has to play
// three more — an attack, a stagger, a hit reaction — so the animation path
// became a parameter, and the loader moved here where a second caller can reach
// it without the cell builder's own state.
//
// Every path below is quoted from the behavior census over the user's own
// install (`logs/hkx-behavior-census.log`, `HKBBehaviorCensusRealDataTests`),
// never from memory: these are file names the vanilla behavior graphs
// themselves reference. Two things about that listing are worth stating because
// they look inconsistent and are not:
//
// * The idle locomotion clips are gendered (`animations\male\mt_idle.hkx`,
//   `animations\female\mt_idle.hkx`) while the combat clips are not
//   (`animations\h2h_attackright.hkx`). That is how the install is laid out.
// * There is no unarmed stagger clip. The census carries `h2h_attackleft`,
//   `h2h_attackright`, `h2h_recoilleft`, `h2h_recoilright` and
//   `h2h_recoiltimed`, but every `staggerback` variant is prefixed by a weapon
//   class (`1hm_`, `2hm_`, `2hw_`). The one-handed small stagger is therefore
//   what an unarmed stand-in plays; all of these ride the same character rig,
//   so the clip binds. It is a substitution, and it is written down rather than
//   silently made.
//
// Documented in docs/engine/combat.md and docs/engine/actor-animation.md.

import Foundation

nonisolated enum ActorAnimationClipLoader {
    /// Where every character animation and skeleton lives.
    static let characterRoot = "meshes\\actors\\character\\"

    /// The gendered idle locomotion clip, which is what an NPC plays when
    /// nothing has asked for anything else.
    static func idleAnimationPath(female: Bool) -> String {
        characterRoot + "animations\\\(female ? "female" : "male")\\mt_idle.hkx"
    }

    /// Direct gait clips named by the vanilla behavior graph census. They are
    /// in-place; the NPC capsule remains the sole movement authority.
    static func gaitAnimationPath(_ gait: LocomotionGait, female: Bool) -> String? {
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
    static func animationPath(for clip: CombatActorClip) -> String {
        characterRoot + "animations\\" + fileName(for: clip)
    }

    /// How long a reaction clip holds the actor before it returns to idle.
    ///
    /// OpenSky numbers: the clip's own duration is readable only after it has
    /// been decoded, and an NPC in this milestone has no behavior graph to end
    /// the state for it. Each is taken from the phase it accompanies in
    /// `CombatBehaviorSettings.standard`, so the animation and the hit land
    /// together. The shipping settings rather than a live machine's, because a
    /// clip is decoded once per skeleton and held for every actor that plays it.
    static func holdSeconds(for clip: CombatActorClip) -> Float {
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

    /// Decodes one clip: the skeleton beside the `.nif`, the animation at
    /// `animationPath`, and the binding that ties them together.
    ///
    /// - Parameters:
    ///   - skeletonMeshPath: the actor's skeleton `.nif`, whose `.hkx` sibling
    ///     carries the rig.
    ///   - animationPath: canonical VFS path of the animation to load.
    ///   - readHKX: how the caller reads a file. Injected rather than taken
    ///     from a stored file system so the cell builder and the combat wiring
    ///     can each supply their own.
    static func clip(
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
