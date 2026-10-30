// Cell-owned actor playback. HKX local tracks, or the pose of the actor's own behaviour
// graph, are composed through the hkaSkeleton parent graph, name-mapped onto each NIF
// skin palette, then uploaded once per render frame. See docs/engine/actor-graphs.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
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

nonisolated public final class ActorAnimationPlayback: SharedPoseAnimation,
    LipHeadMotionApplying
{
    nonisolated private struct State {
        /// The idle clip, or a bounded combat override.
        var clip: ActorAnimationClip
        var locomotionClip: ActorAnimationClip
        /// Animation time the override started at, so it is sampled from its own
        /// frame zero rather than from wherever the shared clock happened to be.
        var overrideStart: Float = 0
        /// Animation time the override ends at. Zero when none is playing.
        var overrideEnd: Float = 0
        var headLook = HeadLook.forward
        var speechHeadMotion = LipHeadMotion.zero
        var weaponsDrawn = false
        /// The actor's running behaviour graph. It replaces the gait and idle clip,
        /// but a combat override still wins while it plays.
        var graph: GraphSource?
    }

    nonisolated private struct GraphSource {
        let skeleton: HKASkeleton
        let boneIndex: SkeletonBoneIndex
        let buffer: PlayerPoseBuffer
        var revision: Int?
        var pose: SkeletonPose?

        /// The newest graph pose, composed once per published revision.
        mutating func current() -> SkeletonPose? {
            let snapshot = buffer.snapshot
            if snapshot.revision != revision {
                revision = snapshot.revision
                pose = snapshot.bones.isEmpty ? nil : (try? SkeletonPoseMath.worldMatrices(
                    skeleton: skeleton, localPoses: snapshot.bones
                )).map { SkeletonPose(bones: boneIndex, matrices: $0) }
            }
            return pose
        }
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
    /// Hand node to sheath node, from `ResolvedActorVisual.sheathNodes`.
    public let sheathNodes: [String: String]
    /// The armour addon models the actor wears; one that names a graph runs it as a sub-graph.
    public let armorAddons: [WornArmorAddon]

    /// The clip currently playing: the idle one, or a bounded combat override.
    public var clip: ActorAnimationClip {
        state.withLock { $0.clip }
    }

    public init(
        actor: FormID,
        clip: ActorAnimationClip,
        models: [RenderModel],
        female: Bool = false,
        transform: float4x4 = matrix_identity_float4x4,
        sheathNodes: [String: String] = [:],
        armorAddons: [WornArmorAddon] = []
    ) {
        self.actor = actor
        self.sheathNodes = sheathNodes
        self.armorAddons = armorAddons
        self.female = female
        self.transform = transform
        idleClip = clip
        state = Mutex(State(clip: clip, locomotionClip: clip))
        var seen = Set<ObjectIdentifier>()
        meshes = models.flatMap(\.meshes).filter {
            $0.isSkinned && seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    /// Plays `clip` for `seconds`, then returns to idle; infinite `seconds` hold it. A
    /// second request replaces the first, so a stagger takes an attack's clip away.
    public func play(
        _ clip: ActorAnimationClip,
        startingAt time: Float,
        forSeconds seconds: Float
    ) {
        guard seconds > 0, !seconds.isNaN else { return }
        state.withLock {
            $0.clip = clip
            $0.overrideStart = time
            $0.overrideEnd = time + seconds
        }
    }

    /// Ends the playing override now, as when a held idle is released.
    public func endOverride() {
        state.withLock {
            $0.clip = $0.locomotionClip
            $0.overrideEnd = 0
            $0.overrideStart = 0
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
        let (clip, clipTime, graphPose) = state.withLock { state in
            if state.overrideEnd > 0, time >= state.overrideEnd {
                state.clip = state.locomotionClip
                state.overrideEnd = 0
                state.overrideStart = 0
            }
            let graphPose = state.overrideEnd == 0 ? state.graph?.current() : nil
            let clipTime = state.overrideEnd > 0 ? time - state.overrideStart : time
            return (state.clip, clipTime, graphPose)
        }
        return graphPose ?? clip.worldPose(at: clipTime)
    }

    /// True when the posed skeleton has `bone`, found without posing it.
    public func hasBone(named bone: String) -> Bool {
        state.withLock { state in
            let bones = state.overrideEnd == 0 ? state.graph?.boneIndex : nil
            return (bones ?? state.clip.boneIndex).index(of: bone) != nil
        }
    }

    /// Hands the pose to the actor's behaviour graph: `pose` is what the graph publishes,
    /// in the bone order of `skeleton`.
    public func attachGraph(skeleton: HKASkeleton, pose: PlayerPoseBuffer) {
        let source = GraphSource(
            skeleton: skeleton, boneIndex: SkeletonBoneIndex(names: skeleton.boneNames),
            buffer: pose
        )
        state.withLock { $0.graph = source }
    }

    /// Returns the actor to its clips.
    public func detachGraph() {
        state.withLock { $0.graph = nil }
    }

    /// True while a behaviour graph poses the actor.
    public var isGraphDriven: Bool {
        state.withLock { $0.graph != nil }
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

    /// A graph-driven actor shares its pose with no other actor.
    public var sharedClipKey: ObjectIdentifier {
        state.withLock { state in
            state.overrideEnd == 0 && state.graph != nil
                ? ObjectIdentifier(self) : ObjectIdentifier(state.clip)
        }
    }

    public func sampleSharedPose(at time: Float) -> SkeletonPose? {
        let graphPose = state.withLock { state in
            state.overrideEnd == 0 ? state.graph?.current() : nil
        }
        return graphPose ?? clip.worldPose(at: time)
    }

    public func apply(
        _ pose: SkeletonPose,
        updating updatedMeshes: inout Set<ObjectIdentifier>
    ) -> Int {
        let (look, skeleton, drawn) = state.withLock { state in
            let graphDriven = state.overrideEnd == 0 && state.graph != nil
            let skeleton = graphDriven ? state.graph?.skeleton : nil
            return (
                state.headLook.adding(state.speechHeadMotion),
                skeleton ?? state.clip.skeleton, state.weaponsDrawn
            )
        }
        let sheathed = WeaponSheathing.apply(sheathNodes, drawn: drawn, to: pose)
        let posed = HeadTrackingCore.apply(look, to: sheathed, parents: skeleton.parentIndices)
        return meshes.applySkinningPose(posed, updating: &updatedMeshes)
    }

    /// False keeps each weapon and the shield on its sheath node.
    public var weaponsDrawn: Bool {
        get { state.withLock { $0.weaponsDrawn } }
        set { state.withLock { $0.weaponsDrawn = newValue } }
    }

    /// The neck and head turn drawn on top of every clip, until changed.
    public var headLook: HeadLook {
        get { state.withLock { $0.headLook } }
        set { state.withLock { $0.headLook = newValue } }
    }

    /// The head turn the current voice line's lip track adds.
    public var speechHeadMotion: LipHeadMotion {
        get { state.withLock { $0.speechHeadMotion } }
        set { state.withLock { $0.speechHeadMotion = newValue } }
    }

    @discardableResult
    public func resetToBindPose() -> Int {
        meshes.resetSkinningPoses()
    }
}

nonisolated public struct ActorAnimationCacheKey: Hashable, Sendable {
    public let skeletonPath: String
    public let female: Bool

    public init(skeletonPath: String, female: Bool) {
        self.skeletonPath = skeletonPath
        self.female = female
    }
}

/// One worn armour addon model.
nonisolated public struct WornArmorAddon: Equatable, Sendable {
    public let armature: FormID
    public let modelPath: String
    public let slots: BodySlots

    public init(armature: FormID, modelPath: String, slots: BodySlots = BodySlots()) {
        self.armature = armature
        self.modelPath = modelPath
        self.slots = slots
    }
}

nonisolated extension ResolvedActorVisual {
    public var wornArmorAddons: [WornArmorAddon] {
        parts.map {
            WornArmorAddon(armature: $0.armature, modelPath: $0.modelPath, slots: $0.slots)
        }
    }
}

nonisolated extension [WornArmorAddon] {
    /// The armatures whose `ARMA` footstep set may apply, feet-slot parts first. A
    /// creature skin such as a horse's names its set on a part with no feet slot.
    public var footstepArmatures: [FormID] {
        let feet = filter { $0.slots.contains(.feet) }
        let rest = filter { !$0.slots.contains(.feet) }
        return (feet + rest).map(\.armature)
    }
}
