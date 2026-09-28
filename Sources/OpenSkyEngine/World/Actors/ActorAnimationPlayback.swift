// Cell-owned direct idle playback (milestone 6.4/6.5). HKX local tracks are
// composed through the hkaSkeleton parent graph, name-mapped onto each NIF
// skin palette, then uploaded once per render frame. No behavior graph or AI.

import Foundation
import simd

nonisolated enum SkeletonPoseError: Error, Equatable {
    case boneIndexOutOfRange(Int)
    case parentCycle(Int)
}

/// Pure pose math: local TRS -> skeleton-world matrices. Kept independent of
/// Metal + file loading so hierarchy and palette math are unit-testable.
nonisolated enum SkeletonPoseMath {
    static func localMatrix(_ pose: HKABonePose) -> float4x4 {
        let rotation = float4x4(pose.rotation)
        let scale = float4x4(diagonal: SIMD4(pose.scale, 1))
        return MatrixMath.translation(pose.translation) * rotation * scale
    }

    static func worldMatrices(
        skeleton: HKASkeleton,
        samples: [HKABoneTransformSample]
    ) throws -> [float4x4] {
        var local = skeleton.referencePose
        for sample in samples {
            guard local.indices.contains(sample.boneIndex) else {
                throw SkeletonPoseError.boneIndexOutOfRange(sample.boneIndex)
            }
            local[sample.boneIndex] = sample.pose
        }
        return try worldMatrices(skeleton: skeleton, localPoses: local)
    }

    /// Composes a dense local pose — one TRS per skeleton bone, which is what a
    /// behavior graph produces (`BehaviorPose.bones`) — through the parent
    /// chain. Bones past the end of `localPoses` keep their reference pose, so a
    /// graph bound to a rig with fewer bones than the skeleton still composes.
    static func worldMatrices(
        skeleton: HKASkeleton,
        localPoses: [HKABonePose]
    ) throws -> [float4x4] {
        var local = skeleton.referencePose
        for index in local.indices where localPoses.indices.contains(index) {
            local[index] = localPoses[index]
        }
        var world = [float4x4?](repeating: nil, count: local.count)
        var visiting = Set<Int>()

        func resolve(_ index: Int) throws -> float4x4 {
            if let resolved = world[index] {
                return resolved
            }
            guard visiting.insert(index).inserted else {
                throw SkeletonPoseError.parentCycle(index)
            }
            defer { visiting.remove(index) }
            let own = localMatrix(local[index])
            let parent = skeleton.parentIndices[index]
            let resolved: float4x4
            if parent == -1 {
                resolved = own
            } else {
                guard world.indices.contains(parent) else {
                    throw SkeletonPoseError.boneIndexOutOfRange(parent)
                }
                resolved = try resolve(parent) * own
            }
            world[index] = resolved
            return resolved
        }

        return try local.indices.map(resolve)
    }
}

nonisolated final class ActorAnimationClip {
    let skeleton: HKASkeleton
    let animation: HKASplineCompressedAnimation
    let binding: HKAAnimationBinding
    /// The `.nif` this rig's skeleton came from, which is also where its
    /// ragdoll bodies and joints live (issue #197). Carried here rather than
    /// re-derived because the clip is the only thing that already knows which
    /// skeleton an actor is using.
    let skeletonMeshPath: String

    init(
        skeleton: HKASkeleton,
        animation: HKASplineCompressedAnimation,
        binding: HKAAnimationBinding,
        skeletonMeshPath: String = ""
    ) {
        self.skeleton = skeleton
        self.animation = animation
        self.binding = binding
        self.skeletonMeshPath = skeletonMeshPath
    }

    /// The rig's bind pose as skeleton-world matrices, in bone order. The frame
    /// a ragdoll's bodies are authored against.
    var bindWorldMatrices: [float4x4] {
        (try? SkeletonPoseMath.worldMatrices(
            skeleton: skeleton, localPoses: skeleton.referencePose
        )) ?? []
    }

    /// The pose at `time` as skeleton-world matrices in bone order, which is
    /// what a ragdoll hand-off reads. Nil where the clip cannot be sampled, the
    /// same condition `namedWorldTransforms(at:)` returns nil on.
    func orderedWorldTransforms(at time: Float) -> [float4x4]? {
        guard let named = namedWorldTransforms(at: time) else { return nil }
        let bind = bindWorldMatrices
        return skeleton.boneNames.enumerated().map { index, name in
            named[name] ?? (bind.indices.contains(index) ? bind[index] : matrix_identity_float4x4)
        }
    }

    func namedWorldTransforms(at time: Float) -> [String: float4x4]? {
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
        var named: [String: float4x4] = [:]
        for (name, transform) in zip(skeleton.boneNames, world) where named[name] == nil {
            named[name] = transform
        }
        return named
    }
}

nonisolated enum ActorAnimationLoadError: LocalizedError {
    case unsupportedSkeleton(String)
    case missing(String)
    case noRig(String)
    case noClip(String)
    case noBinding(String)
    case invalid(String, any Error)

    var errorDescription: String? {
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

/// RenderScene stores these references. Removing a resident CellScene removes
/// its playback objects; decoded immutable clip assets may remain cache-hot.
nonisolated protocol RenderAnimation: AnyObject {
    @discardableResult
    func update(at time: Float) -> Int

    /// Restore bind/reference state for a true animation-off A/B frame.
    @discardableResult
    func resetToBindPose() -> Int
}

nonisolated extension RenderAnimation {
    @discardableResult
    func resetToBindPose() -> Int {
        0
    }
}

nonisolated final class ActorAnimationPlayback: RenderAnimation {
    let actor: FormID
    let female: Bool
    /// The clip currently sounding: the idle one, or a bounded override a
    /// combat reaction asked for (issue #374).
    private(set) var clip: ActorAnimationClip
    /// The clip this actor returns to when an override ends.
    private let idleClip: ActorAnimationClip
    private var locomotionClip: ActorAnimationClip
    /// Animation time the override started at, so it is sampled from its own
    /// frame zero rather than from wherever the shared clock happened to be.
    private var overrideStart: Float = 0
    /// Animation time the override ends at. Zero when none is playing.
    private var overrideEnd: Float = 0
    private let meshes: [RenderMesh]

    init(
        actor: FormID,
        clip: ActorAnimationClip,
        models: [RenderModel],
        female: Bool = false
    ) {
        self.actor = actor
        self.female = female
        self.clip = clip
        idleClip = clip
        locomotionClip = clip
        var seen = Set<ObjectIdentifier>()
        meshes = models.flatMap(\.meshes).filter {
            $0.isSkinned && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    /// Plays `clip` for `seconds`, then returns to the idle one (issue #374).
    ///
    /// A second request replaces the first rather than queueing: a stagger that
    /// interrupts an attack has to take the attack's clip away, which is the
    /// same rule the player's graph follows.
    func play(_ clip: ActorAnimationClip, startingAt time: Float, forSeconds seconds: Float) {
        guard seconds > 0, seconds.isFinite else { return }
        self.clip = clip
        overrideStart = time
        overrideEnd = time + seconds
    }

    /// Selects the in-place gait clip a kinematic NPC drive resolved. Combat
    /// overrides remain authoritative until their bounded hold expires.
    func setLocomotionClip(_ clip: ActorAnimationClip?) {
        locomotionClip = clip ?? idleClip
        if overrideEnd == 0 {
            self.clip = locomotionClip
        }
    }

    /// Whether a bounded override is playing as of `time`.
    func isOverriding(at time: Float) -> Bool {
        overrideEnd > 0 && time < overrideEnd
    }

    /// The pose to draw at `time`, with an expired override already retired.
    /// The one place the override's own clock is applied, so every consumer —
    /// skinning here, the ragdoll hand-off in the app — reads the same pose.
    func pose(at time: Float) -> [String: float4x4]? {
        if overrideEnd > 0, time >= overrideEnd {
            clip = locomotionClip
            overrideEnd = 0
            overrideStart = 0
        }
        return clip.namedWorldTransforms(at: overrideEnd > 0 ? time - overrideStart : time)
    }

    @discardableResult
    func update(at time: Float) -> Int {
        guard let transforms = pose(at: time) else { return 0 }
        var updatedMeshes = Set<ObjectIdentifier>()
        return apply(transforms, updating: &updatedMeshes)
    }

    func apply(
        _ transforms: [String: float4x4],
        updating updatedMeshes: inout Set<ObjectIdentifier>
    ) -> Int {
        meshes.reduce(0) { count, mesh in
            guard updatedMeshes.insert(ObjectIdentifier(mesh)).inserted else { return count }
            return count + mesh.updateSkinningPose(transforms)
        }
    }

    @discardableResult
    func resetToBindPose() -> Int {
        meshes.reduce(0) { $0 + $1.resetSkinningPose() }
    }
}

nonisolated struct ActorAnimationCacheKey: Hashable {
    let skeletonPath: String
    let female: Bool
}

nonisolated extension CellSceneBuilder {
    nonisolated func makeAnimationPlayback(
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
            female: assembly.visual.appearance.isFemale.value
        ))
    }

    nonisolated private func loadAnimationClip(
        key: ActorAnimationCacheKey
    ) throws -> ActorAnimationClip {
        try ActorAnimationClipLoader.clip(
            skeletonMeshPath: key.skeletonPath,
            animationPath: ActorAnimationClipLoader.idleAnimationPath(female: key.female),
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
