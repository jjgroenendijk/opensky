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

    /// The idle clips to try, in order, for the skeleton at `skeletonMeshPath`: the
    /// gendered one for a character, the candidates beside a creature's skeleton.
    public static func idleAnimationPaths(skeletonMeshPath: String, female: Bool) -> [String] {
        guard let location = CreatureClipNames.location(skeletonMeshPath: skeletonMeshPath) else {
            return [idleAnimationPath(female: female)]
        }
        return CreatureClipNames.paths(CreatureClipNames.idle, at: location)
    }

    /// Direct gait clips named by the vanilla behavior graph census. They are
    /// in-place; the NPC capsule remains the sole movement authority.
    public static func gaitAnimationPath(_ gait: LocomotionGait, female: Bool) -> String? {
        gaitFileName(gait).map {
            characterRoot + "animations\\\(female ? "female" : "male")\\mt_" + $0
        }
    }

    /// The gait clips to try, in order, as `idleAnimationPaths(skeletonMeshPath:female:)`.
    /// Empty for a gait with no direct clip.
    public static func gaitAnimationPaths(
        _ gait: LocomotionGait, skeletonMeshPath: String, female: Bool
    ) -> [String] {
        guard let location = CreatureClipNames.location(skeletonMeshPath: skeletonMeshPath) else {
            return gaitAnimationPath(gait, female: female).map { [$0] } ?? []
        }
        return CreatureClipNames.paths(CreatureClipNames.gait(gait), at: location)
    }

    /// The rider's clip on a horse: idle when the horse stands, else its gait.
    public static func riderAnimationPath(_ gait: LocomotionGait?) -> String {
        let name = gait.flatMap(gaitFileName) ?? "idle.hkx"
        return characterRoot + "animations\\horse_rider\\" + name
    }

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
            skeletonMeshPath.hasPrefix(characterRoot)
            || CreatureClipNames.location(skeletonMeshPath: skeletonMeshPath) != nil,
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

    /// Decodes the first of `animationPaths` that `exists`, else tries the first, so a
    /// missing clip still reports its path.
    public static func clip(
        skeletonMeshPath: String,
        animationPaths: [String],
        exists: (String) -> Bool,
        readHKX: (String) throws -> HKXFile
    ) throws -> ActorAnimationClip {
        guard let path = chosenPath(animationPaths, exists: exists) else {
            throw ActorAnimationLoadError.noClip(skeletonMeshPath)
        }
        return try clip(skeletonMeshPath: skeletonMeshPath, animationPath: path, readHKX: readHKX)
    }

    static func chosenPath(_ paths: [String], exists: (String) -> Bool) -> String? {
        paths.first(where: exists) ?? paths.first
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
