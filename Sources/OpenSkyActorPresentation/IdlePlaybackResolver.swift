// Turns a chosen IDLE into what to play: the clip its `ENAM` event reaches in
// the behavior graph, or a clip named after the event, plus the ANIO prop the
// graph loads for it. See docs/engine/idle-runtime.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import Synchronization

/// Which way an idle reached its clip.
nonisolated public enum IdleServedPath: Equatable, Sendable {
    /// The event's transition in the behavior graph led to the clip.
    case graphEvent(behaviorFiles: [String])
    /// No transition names the event; a clip file named after it exists.
    case namedClip
    case none(IdlePlaybackMiss)
}

nonisolated public enum IdlePlaybackMiss: Equatable, Sendable {
    case noEvent
    /// The graph has no transition on the event and no clip carries its name.
    case eventNotInGraph
    /// The graph names a clip that the install does not have.
    case clipMissing(String)
}

/// The prop an idle shows, or why it shows none.
nonisolated public enum IdleProp: Equatable, Sendable {
    case attached(editorID: String, modelPath: String, bone: String)
    case none
    case modelMissing(editorID: String)
    /// The model names no `Prn` parent bone.
    case noBone(editorID: String)
}

/// An `ANIO` a clip annotation names, such as `AnimObjDraw.AnimObjectSkeletonKey`.
nonisolated public struct IdleAnimationObject: Equatable, Sendable {
    public let editorID: String
    public let prop: IdleProp
    /// The `BNAM` event that takes the object off again.
    public let unloadEvent: String?
}

nonisolated public struct IdlePlaybackPlan: Equatable, Sendable {
    public let event: String?
    public let path: IdleServedPath
    /// The clip's path in the virtual file system, nil when nothing plays.
    public let clipPath: String?
    public let prop: IdleProp
    /// What the graph's state sends as the idle starts and ends, such as `ExitCartEnd`.
    public var notify = BehaviorStateNotify()
    /// The state's clip loops, so the idle holds until another one replaces it.
    public var loops = false
    /// The graph state the event enters; nil when the clip was found by name.
    public var state: String?
    /// Events the clip's generator raises, such as `KillActor`.
    public var triggers: [BehaviorClipTriggerEvent] = []
    /// Clips that play after the first one, each a path in the virtual file system.
    public var followUps: [IdlePlanSegment] = []
    /// Where the actor's graph is when the chain ends.
    public var position: BehaviorStatePosition?
    /// The objects the clips' annotations show while they play.
    public var animationObjects: [IdleAnimationObject] = []

    /// Every clip path the plan plays, in order.
    public var clipPaths: [String] {
        (clipPath.map { [$0] } ?? []) + followUps.map(\.clipPath)
    }
}

/// One clip that a plan plays after its first.
nonisolated public struct IdlePlanSegment: Equatable, Sendable {
    public let clipPath: String
    public let loops: Bool
    public let triggers: [BehaviorClipTriggerEvent]
}

/// Caches decoded behavior files and prop bones for the session.
nonisolated public final class IdlePlaybackResolver {
    private let files: any GameFileSource
    private let animatedObjects: TypedRecordStore<AnimatedObject>
    /// One per project folder, because referenced behavior names are relative.
    private var indexes: [String: BehaviorEventClipIndex] = [:]
    private var plans: [IdlePlanKey: IdlePlaybackPlan] = [:]
    private var propBones: [String: String?] = [:]
    private var skeletonBones: [String: [String]] = [:]

    public init(files: any GameFileSource, animatedObjects: TypedRecordStore<AnimatedObject>) {
        self.files = files
        self.animatedObjects = animatedObjects
    }

    private func index(project: String) -> BehaviorEventClipIndex {
        if let index = indexes[project] {
            return index
        }
        let files = files
        let index = BehaviorEventClipIndex { name in
            guard
                let path = Self.behaviorPath(name, project: project),
                let data = try? files.contents(forPath: path),
                let file = try? HKXFile(data: data)
            else { return nil }
            return try? HKXObjectGraph(file: file)
        }
        indexes[project] = index
        return index
    }

    public func plan(
        for idle: ResolvedRecord<IdleAnimation>, from position: BehaviorStatePosition? = nil
    ) -> IdlePlaybackPlan {
        let key = IdlePlanKey(idle, from: position)
        if let cached = plans[key] {
            return cached
        }
        let plan = resolve(idle.record, from: position)
        plans[key] = plan
        return plan
    }

    private func resolve(
        _ idle: IdleAnimation, from position: BehaviorStatePosition?
    ) -> IdlePlaybackPlan {
        guard let event = idle.animationEvent, !event.isEmpty else {
            return IdlePlaybackPlan(event: nil, path: .none(.noEvent), clipPath: nil, prop: .none)
        }
        let project = Self.projectFolder(of: idle.fileName)
        if
            let behavior = idle.fileName,
            let clip = index(project: project)
                .clip(forEvent: event, behaviorFile: behavior, from: position)
        {
            return plan(event: event, clip: clip, project: project)
        }
        guard
            let named = Self.namedClipPaths(event: event, project: project)
                .first(where: files.exists)
        else {
            return IdlePlaybackPlan(
                event: event, path: .none(.eventNotInGraph), clipPath: nil, prop: .none
            )
        }
        var plan = IdlePlaybackPlan(event: event, path: .namedClip, clipPath: named, prop: .none)
        plan.animationObjects = animationObjects(clipPaths: [named], project: project)
        return plan
    }

    private func plan(
        event: String, clip: BehaviorEventClip, project: String
    ) -> IdlePlaybackPlan {
        let path = Self.normalized(project + clip.animationName)
        let followUps = clip.followUps.map { segment in
            IdlePlanSegment(
                clipPath: Self.normalized(project + segment.animationName),
                loops: segment.loops, triggers: segment.triggers
            )
        }
        if let missing = ([path] + followUps.map(\.clipPath)).first(where: { !files.exists($0) }) {
            return IdlePlaybackPlan(
                event: event, path: .none(.clipMissing(missing)), clipPath: nil, prop: .none
            )
        }
        var plan = IdlePlaybackPlan(
            event: event,
            path: .graphEvent(behaviorFiles: clip.behaviorFiles),
            clipPath: path,
            prop: prop(payloads: clip.payloads, project: project),
            notify: clip.notify,
            loops: followUps.last?.loops ?? clip.loops,
            state: clip.stateName,
            triggers: clip.triggers,
            followUps: followUps,
            position: clip.position
        )
        plan.animationObjects = animationObjects(clipPaths: plan.clipPaths, project: project)
        return plan
    }

    /// The `ANIO`s the clips' annotations name. A clip whose bytes do not hold the
    /// event name, which is nearly every clip, is not decoded.
    private func animationObjects(clipPaths: [String], project: String) -> [IdleAnimationObject] {
        var texts: [String] = []
        for path in clipPaths {
            guard
                let data = try? files.contents(forPath: path),
                data.range(of: Data("nimObj".utf8)) != nil,
                let graph = try? HKXObjectGraph.decode(data),
                let clips = try? HKASplineCompressedAnimation.animations(in: graph)
            else { continue }
            texts += clips.flatMap(\.annotations).map(\.text)
        }
        return AnimationObjectEvent.editorIDs(in: texts).map { editorID in
            IdleAnimationObject(
                editorID: editorID,
                prop: prop(payloads: [editorID], project: project),
                unloadEvent: animatedObjects.record(editorID: editorID)?.record.unloadEvent
            )
        }
    }

    /// Clips named after an event no transition takes. The second form is the clip of the
    /// `MT_<stem>` state in `idlebehavior.hkx`, for events such as `idle_A_sway_fastTrans`.
    static func namedClipPaths(event: String, project: String) -> [String] {
        var stem = event.lowercased()
        if stem.hasSuffix("trans") {
            stem.removeLast("trans".count)
        }
        return [
            normalized(project + "animations\\" + event + ".hkx"),
            normalized(project + "animations\\male\\mt_" + stem + ".hkx")
        ]
    }

    /// The first payload that names an ANIO record.
    private func prop(payloads: [String], project: String) -> IdleProp {
        for payload in payloads {
            guard let object = animatedObjects.record(editorID: payload) else { continue }
            guard
                let model = object.record.model?.path,
                files.exists(Self.normalized("meshes\\" + model))
            else { return .modelMissing(editorID: payload) }
            guard let bone = parentBone(of: Self.normalized("meshes\\" + model)) else {
                return .noBone(editorID: payload)
            }
            let skeletonBone = Self.skeletonBone(bone, in: bones(of: project))
            return .attached(editorID: payload, modelPath: model, bone: skeletonBone)
        }
        return .none
    }

    private func parentBone(of path: String) -> String? {
        if let cached = propBones[path] {
            return cached
        }
        let bone = (try? NIFFile(data: files.contents(forPath: path)))
            .flatMap(NIFStringExtraData.parentBone(in:))
        propBones[path] = bone
        return bone
    }

    private func bones(of project: String) -> [String] {
        if let cached = skeletonBones[project] {
            return cached
        }
        let path = project + "character assets\\skeleton.hkx"
        let bones = (try? HKASkeleton.skeletons(in: HKXFile(data: files.contents(forPath: path))))?
            .flatMap(\.boneNames) ?? []
        skeletonBones[project] = bones
        return bones
    }

    /// Some props name `NPC R Hand` where the skeleton has `NPC R Hand [RHnd]`.
    static func skeletonBone(_ parent: String, in bones: [String]) -> String {
        guard !bones.contains(parent) else { return parent }
        let prefix = parent.lowercased() + " ["
        return bones.first { $0.lowercased().hasPrefix(prefix) } ?? parent
    }

    /// `meshes\actors\character\` for `Actors\Character\Behaviors\0_Master.hkx`:
    /// clip and behavior names are relative to the folder above `Behaviors`.
    static func projectFolder(of behaviorFile: String?) -> String {
        let lower = (behaviorFile ?? "").lowercased()
        guard let range = lower.range(of: "behaviors\\", options: .backwards) else {
            return "meshes\\actors\\character\\"
        }
        return "meshes\\" + lower[..<range.lowerBound]
    }

    /// A root DNAM path is relative to `meshes`; a referenced behavior is
    /// relative to its project folder.
    static func behaviorPath(_ name: String, project: String) -> String? {
        let lower = name.lowercased()
        guard lower.hasSuffix(".hkx") else { return nil }
        return normalized(lower.hasPrefix("actors\\") ? "meshes\\" + lower : project + lower)
    }

    /// Lowercased, with `..` segments folded.
    static func normalized(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.lowercased().replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\")
        {
            switch part {
            case "..": _ = parts.popLast()
            case ".": continue
            default: parts.append(part)
            }
        }
        return parts.joined(separator: "\\")
    }
}

/// One idle's plan request from where the actor's graph is. Equal by record identity.
nonisolated public struct IdlePlanKey: Hashable, Sendable {
    public let idle: ResolvedRecord<IdleAnimation>
    public let position: BehaviorStatePosition?

    public init(
        _ idle: ResolvedRecord<IdleAnimation>,
        from position: BehaviorStatePosition? = nil
    ) {
        self.idle = idle
        self.position = position
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.idle.id == rhs.idle.id && lhs.position == rhs.position
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(idle.id)
        hasher.combine(position)
    }
}

public typealias IdlePlanLoader = AssetLoader<IdlePlanKey, IdlePlaybackPlan>

nonisolated extension IdlePlaybackResolver {
    /// The plan decode a worker runs. The resolver and its graph caches live on the worker.
    public static func planLoad(
        files: any GameFileSource,
        animatedObjects: TypedRecordStore<AnimatedObject>
    ) -> @Sendable (IdlePlanKey) throws -> IdlePlaybackPlan {
        let box = IdlePlaybackResolverBox(
            IdlePlaybackResolver(files: files, animatedObjects: animatedObjects)
        )
        return { key in box.resolver.withLock { $0.plan(for: key.idle, from: key.position) } }
    }
}

nonisolated private final class IdlePlaybackResolverBox: Sendable {
    let resolver: Mutex<IdlePlaybackResolver>

    init(_ resolver: sending IdlePlaybackResolver) {
        self.resolver = Mutex(resolver)
    }
}
