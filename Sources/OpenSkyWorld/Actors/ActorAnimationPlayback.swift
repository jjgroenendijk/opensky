// Cell-owned direct idle playback (milestone 6.4/6.5). HKX local tracks are
// composed through the hkaSkeleton parent graph, name-mapped onto each NIF
// skin palette, then uploaded once per render frame. No behavior graph or AI.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import simd
import Synchronization

nonisolated public final class ActorAnimationClip: Sendable {
    public let skeleton: HKASkeleton
    public let animation: HKASplineCompressedAnimation
    public let binding: HKAAnimationBinding
    /// The `.nif` this rig's skeleton came from, which also holds its ragdoll bodies
    /// and joints.
    public let skeletonMeshPath: String
    /// The skeleton's bone names, indexed once so skinning can map to bone order.
    public let boneIndex: SkeletonBoneIndex

    public init(
        skeleton: HKASkeleton,
        animation: HKASplineCompressedAnimation,
        binding: HKAAnimationBinding,
        skeletonMeshPath: String = ""
    ) {
        self.skeleton = skeleton
        self.animation = animation
        self.binding = binding
        self.skeletonMeshPath = skeletonMeshPath
        boneIndex = SkeletonBoneIndex(names: skeleton.boneNames)
    }

    /// The rig's bind pose as skeleton-world matrices, in bone order. The frame
    /// a ragdoll's bodies are authored against.
    public var bindWorldMatrices: [float4x4] {
        (try? SkeletonPoseMath.worldMatrices(
            skeleton: skeleton, localPoses: skeleton.referencePose
        )) ?? []
    }

    /// The pose at `time` as skeleton-world matrices in bone order, which is
    /// what a ragdoll hand-off reads. Nil where the clip cannot be sampled, the
    /// same condition `namedWorldTransforms(at:)` returns nil on.
    public func orderedWorldTransforms(at time: Float) -> [float4x4]? {
        guard let pose = worldPose(at: time) else { return nil }
        let bind = bindWorldMatrices
        return skeleton.boneNames.indices.map { index in
            // A repeated name poses as its first bone, as skinning reads it.
            let source = boneIndex.index(of: skeleton.boneNames[index]) ?? index
            if source < pose.matrices.count {
                return pose.matrices[source]
            }
            return bind.indices.contains(index) ? bind[index] : matrix_identity_float4x4
        }
    }

    public func namedWorldTransforms(at time: Float) -> [String: float4x4]? {
        worldPose(at: time)?.named
    }

    /// The pose at `time` in skeleton bone order. Nil where the clip cannot be sampled.
    public func worldPose(at time: Float) -> SkeletonPose? {
        guard animation.duration > 0 else { return nil }
        let sampleTime = time.truncatingRemainder(dividingBy: animation.duration)
        guard
            let samples = try? animation.boneLocalTransforms(
                at: sampleTime,
                binding: binding
            ),
            let world = try? SkeletonPoseMath.worldMatrices(
                skeleton: skeleton,
                samples: samples
            )
        else { return nil }
        return SkeletonPose(bones: boneIndex, matrices: world)
    }
}

nonisolated public enum ActorAnimationLoadError: LocalizedError {
    case unsupportedSkeleton(String)
    case missing(String)
    case noRig(String)
    case noClip(String)
    case noBinding(String)
    case invalid(String, any Error)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSkeleton(path):
            "no verified direct idle path for skeleton \(path)"
        case let .missing(path):
            "animation asset missing: \(path)"
        case let .noRig(path):
            "no hkaSkeleton rig in \(path)"
        case let .noClip(path):
            "no spline animation in \(path)"
        case let .noBinding(path):
            "no animation binding in \(path)"
        case let .invalid(path, error):
            "invalid animation asset \(path): \(String(describing: error))"
        }
    }
}

nonisolated public final class ActorAnimationPlayback: SharedPoseAnimation {
    nonisolated private struct State {
        /// The idle clip, or a bounded combat override.
        var clip: ActorAnimationClip
        var locomotionClip: ActorAnimationClip
        /// Animation time the override started at, so it is sampled from its own
        /// frame zero rather than from wherever the shared clock happened to be.
        var overrideStart: Float = 0
        /// Animation time the override ends at. Zero when none is playing.
        var overrideEnd: Float = 0
    }

    public let actor: FormID
    public let female: Bool
    /// Where the cell build drew the actor, so a prop drawn later lands on it.
    public let transform: float4x4
    /// The clip this actor returns to when an override ends.
    private let idleClip: ActorAnimationClip
    /// Changed on the main actor after the build queue hands the scene over.
    private let state: Mutex<State>
    private let meshes: [RenderMesh]

    /// The clip currently playing: the idle one, or a bounded combat override.
    public var clip: ActorAnimationClip {
        state.withLock { $0.clip }
    }

    public init(
        actor: FormID,
        clip: ActorAnimationClip,
        models: [RenderModel],
        female: Bool = false,
        transform: float4x4 = matrix_identity_float4x4
    ) {
        self.actor = actor
        self.female = female
        self.transform = transform
        idleClip = clip
        state = Mutex(State(clip: clip, locomotionClip: clip))
        var seen = Set<ObjectIdentifier>()
        meshes = models.flatMap(\.meshes).filter {
            $0.isSkinned && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    /// Plays `clip` for `seconds`, then returns to idle. A second request replaces
    /// the first, so a stagger takes an attack's clip away.
    public func play(
        _ clip: ActorAnimationClip,
        startingAt time: Float,
        forSeconds seconds: Float
    ) {
        guard seconds > 0, seconds.isFinite else { return }
        state.withLock {
            $0.clip = clip
            $0.overrideStart = time
            $0.overrideEnd = time + seconds
        }
    }

    /// Selects the in-place gait clip a kinematic NPC drive resolved. Combat
    /// overrides remain authoritative until their bounded hold expires.
    public func setLocomotionClip(_ clip: ActorAnimationClip?) {
        state.withLock {
            $0.locomotionClip = clip ?? idleClip
            if $0.overrideEnd == 0 {
                $0.clip = $0.locomotionClip
            }
        }
    }

    /// The skeleton-ordered pose to draw at `time`, with an expired override retired.
    /// The one place the override's own clock is applied, so every consumer —
    /// skinning here, the ragdoll hand-off in the app — reads the same pose.
    public func skeletonPose(at time: Float) -> SkeletonPose? {
        let (clip, clipTime) = state.withLock { state in
            if state.overrideEnd > 0, time >= state.overrideEnd {
                state.clip = state.locomotionClip
                state.overrideEnd = 0
                state.overrideStart = 0
            }
            let clipTime = state.overrideEnd > 0 ? time - state.overrideStart : time
            return (state.clip, clipTime)
        }
        return clip.worldPose(at: clipTime)
    }

    @discardableResult
    public func update(at time: Float) -> Int {
        guard let pose = skeletonPose(at: time) else { return 0 }
        var updatedMeshes = Set<ObjectIdentifier>()
        return apply(pose, updating: &updatedMeshes)
    }

    public var actorFormID: UInt32 {
        actor.rawValue
    }

    public var sharedClipKey: ObjectIdentifier {
        ObjectIdentifier(clip)
    }

    public func sampleSharedPose(at time: Float) -> SkeletonPose? {
        clip.worldPose(at: time)
    }

    public func apply(
        _ pose: SkeletonPose,
        updating updatedMeshes: inout Set<ObjectIdentifier>
    ) -> Int {
        meshes.applySkinningPose(pose, updating: &updatedMeshes)
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        meshes.resetSkinningPoses()
    }
}

nonisolated public struct ActorAnimationCacheKey: Hashable, Sendable {
    public let skeletonPath: String
    public let female: Bool
}

nonisolated extension CellSceneBuilder {
    nonisolated public func makeAnimationPlayback(
        assembly: ActorAssembly<ActorRenderAsset>
    ) -> Result<ActorAnimationPlayback, ActorAnimationLoadError> {
        guard let skeletonPath = assembly.visual.skeletonPath else {
            return .failure(.unsupportedSkeleton("<missing>"))
        }
        let normalizedPath: String
        do {
            normalizedPath = try VirtualFileSystem.normalize(skeletonPath)
        } catch {
            return .failure(.unsupportedSkeleton(skeletonPath))
        }
        let meshPath = normalizedPath.hasPrefix("meshes\\")
            ? normalizedPath : "meshes\\" + normalizedPath
        let key = ActorAnimationCacheKey(
            skeletonPath: meshPath,
            female: assembly.visual.appearance.isFemale.value
        )
        let clip: ActorAnimationClip
        if let cached = actorAnimationClips[key] {
            clip = cached
        } else {
            do {
                clip = try loadAnimationClip(key: key)
                actorAnimationClips[key] = clip
            } catch let error as ActorAnimationLoadError {
                return .failure(error)
            } catch {
                return .failure(.invalid(key.skeletonPath, error))
            }
        }
        return .success(ActorAnimationPlayback(
            actor: assembly.actor,
            clip: clip,
            models: assembly.models.map(\.asset.model),
            female: assembly.visual.appearance.isFemale.value,
            transform: assembly.transform
        ))
    }

    nonisolated private func loadAnimationClip(
        key: ActorAnimationCacheKey
    ) throws -> ActorAnimationClip {
        try ActorAnimationClipLoader.clip(
            skeletonMeshPath: key.skeletonPath,
            animationPath: ActorAnimationClipLoader.idleAnimationPath(
                skeletonMeshPath: key.skeletonPath, female: key.female
            ),
            readHKX: readHKX
        )
    }

    nonisolated private func readHKX(path: String) throws -> HKXFile {
        guard let fileSystem, let data = try? fileSystem.contents(forPath: path) else {
            throw ActorAnimationLoadError.missing(path)
        }
        do {
            return try HKXFile(data: data)
        } catch {
            throw ActorAnimationLoadError.invalid(path, error)
        }
    }
}
