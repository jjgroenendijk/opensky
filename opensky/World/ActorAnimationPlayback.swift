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

    init(
        skeleton: HKASkeleton,
        animation: HKASplineCompressedAnimation,
        binding: HKAAnimationBinding
    ) {
        self.skeleton = skeleton
        self.animation = animation
        self.binding = binding
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
}

nonisolated final class ActorAnimationPlayback: RenderAnimation {
    let actor: FormID
    let clip: ActorAnimationClip
    private let meshes: [RenderMesh]

    init(actor: FormID, clip: ActorAnimationClip, models: [RenderModel]) {
        self.actor = actor
        self.clip = clip
        var seen = Set<ObjectIdentifier>()
        meshes = models.flatMap(\.meshes).filter {
            $0.isSkinned && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    @discardableResult
    func update(at time: Float) -> Int {
        guard let transforms = clip.namedWorldTransforms(at: time) else { return 0 }
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
}

nonisolated struct ActorAnimationCacheKey: Hashable {
    let skeletonPath: String
    let female: Bool
}

extension CellSceneBuilder {
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
            models: assembly.models.map(\.asset.model)
        ))
    }

    nonisolated private func loadAnimationClip(
        key: ActorAnimationCacheKey
    ) throws -> ActorAnimationClip {
        let characterRoot = "meshes\\actors\\character\\"
        guard key.skeletonPath.hasPrefix(characterRoot) else {
            throw ActorAnimationLoadError.unsupportedSkeleton(key.skeletonPath)
        }
        guard key.skeletonPath.hasSuffix(".nif") else {
            throw ActorAnimationLoadError.unsupportedSkeleton(key.skeletonPath)
        }
        let skeletonPath = String(key.skeletonPath.dropLast(4)) + ".hkx"
        let gender = key.female ? "female" : "male"
        let animationPath = characterRoot + "animations\\\(gender)\\mt_idle.hkx"
        let skeletonFile = try readHKX(path: skeletonPath)
        let animationFile = try readHKX(path: animationPath)

        let bindings = try HKAAnimationBinding.bindings(in: animationFile)
        guard let binding = bindings.first else {
            throw ActorAnimationLoadError.noBinding(animationPath)
        }
        let animations = try HKASplineCompressedAnimation.animations(in: animationFile)
        let animation = animations.first { candidate in
            binding.animationTarget == HKXPointerTarget(
                sectionIndex: candidate.objectSectionIndex,
                dataOffset: candidate.objectDataOffset
            )
        } ?? animations.first
        guard let animation else {
            throw ActorAnimationLoadError.noClip(animationPath)
        }
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
            binding: binding
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
