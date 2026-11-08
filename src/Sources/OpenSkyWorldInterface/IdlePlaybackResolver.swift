import Foundation
public import OpenSkyBehavior
public import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
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

    public init(
        editorID: String,
        prop: IdleProp,
        unloadEvent: String?
    ) {
        self.editorID = editorID
        self.prop = prop
        self.unloadEvent = unloadEvent
    }
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
    /// How the first clip moves the actor, such as a chair exit stepping it aside.
    public var rootMotion: AnimationRootMotion?

    /// Every clip path the plan plays, in order.
    public var clipPaths: [String] {
        (clipPath.map { [$0] } ?? []) + followUps.map(\.clipPath)
    }

    public init(
        event: String?,
        path: IdleServedPath,
        clipPath: String?,
        prop: IdleProp,
        notify: BehaviorStateNotify = BehaviorStateNotify(),
        loops: Bool = false,
        state: String? = nil,
        triggers: [BehaviorClipTriggerEvent] = [],
        followUps: [IdlePlanSegment] = [],
        position: BehaviorStatePosition? = nil,
        animationObjects: [IdleAnimationObject] = [],
        rootMotion: AnimationRootMotion? = nil
    ) {
        self.event = event
        self.path = path
        self.clipPath = clipPath
        self.prop = prop
        self.notify = notify
        self.loops = loops
        self.state = state
        self.triggers = triggers
        self.followUps = followUps
        self.position = position
        self.animationObjects = animationObjects
        self.rootMotion = rootMotion
    }
}

/// One clip that a plan plays after its first.
nonisolated public struct IdlePlanSegment: Equatable, Sendable {
    public let clipPath: String
    public let loops: Bool
    public let triggers: [BehaviorClipTriggerEvent]

    public init(
        clipPath: String,
        loops: Bool,
        triggers: [BehaviorClipTriggerEvent]
    ) {
        self.clipPath = clipPath
        self.loops = loops
        self.triggers = triggers
    }
}
