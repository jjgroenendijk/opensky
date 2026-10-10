// Runs the behaviour graph of each resident animated object: a trap, a door, a
// lever. Papyrus raises graph events by name and waits for the events a graph
// fires. The graph rules live in `BehaviorGraphInstance`.
// See docs/engine/object-animation.md.

import Foundation
import OpenSkyBehavior
import OpenSkyGameData

/// What the object coordinator reads from the session.
public protocol ObjectBehaviorWorld: AnyObject {
    /// The animated objects of every resident cell.
    func residentAnimatedObjects() -> [CellAnimatedObject]
}

/// One line of the object animation panel.
nonisolated public struct ObjectAnimationRow: Equatable, Sendable {
    public let reference: UInt32
    public let project: String
    public let events: [String]
    public let activeState: String?

    public init(reference: UInt32, project: String, events: [String], activeState: String?) {
        self.reference = reference
        self.project = project
        self.events = events
        self.activeState = activeState
    }
}

public final class ObjectBehaviorCoordinator {
    final class Running {
        let object: CellAnimatedObject
        let instance: BehaviorGraphInstance
        let clips: InstallBehaviorClipSource

        init(
            object: CellAnimatedObject,
            instance: BehaviorGraphInstance,
            clips: InstallBehaviorClipSource
        ) {
            self.object = object
            self.instance = instance
            self.clips = clips
        }
    }

    struct Wait {
        let event: String
        let token: UInt64
    }

    /// Papyrus message tokens start at 1; animation waits use their own range.
    public static let firstToken: UInt64 = 1 << 48

    weak var world: (any ObjectBehaviorWorld)?
    private var files: (any GameFileSource)?
    private(set) var running: [UInt32: Running] = [:]
    private var waits: [UInt32: [Wait]] = [:]
    private var nextToken = firstToken
    /// Off holds every object in the pose it has.
    public var isEnabled = true
    /// Each event a graph fires, as `(reference, event name)`.
    public var onAnimationEvent: ((UInt32, String) -> Void)?
    /// A wait that finished, by its token; true when its event fired.
    public var onWaitFinished: ((UInt64, Bool) -> Void)?

    /// `settings` gives the persisted switch.
    public init(settings: PlayerSettingsStore? = nil) {
        if let settings {
            isEnabled = settings.bool(.objectAnimation)
        }
    }

    public func attach(world: any ObjectBehaviorWorld, files: any GameFileSource) {
        self.world = world
        self.files = files
    }

    /// Starts graphs for new objects and drops departed ones. A rebuilt cell brings
    /// a new pose buffer, so its object restarts at its first state.
    public func sync() {
        let resident = world?.residentAnimatedObjects() ?? []
        var seen = Set<UInt32>()
        for object in resident where seen.insert(object.reference).inserted {
            if let current = running[object.reference], current.object.pose === object.pose {
                continue
            }
            running[object.reference] = start(object)
        }
        for reference in running.keys where !seen.contains(reference) {
            running.removeValue(forKey: reference)
            for wait in waits.removeValue(forKey: reference) ?? [] {
                onWaitFinished?(wait.token, false)
            }
        }
    }

    /// Steps every graph in reference order and publishes the poses.
    public func tick(deltaTime: Float) {
        for reference in running.keys.sorted() {
            guard let entry = running[reference] else { continue }
            entry.clips.drain()
            guard isEnabled else { continue }
            let result = entry.instance.update(deltaTime: deltaTime)
            if !result.bones.isEmpty {
                entry.object.pose.publish(result.bones)
            }
            for name in result.firedEvents.compactMap(\.name) {
                onAnimationEvent?(reference, name)
                finishWaits(on: reference, event: name)
            }
        }
    }

    /// Raises `event` on the object's graph. False when the object has no graph
    /// or the graph declares no such event.
    @discardableResult
    public func send(_ event: String, to reference: UInt32) -> Bool {
        running[reference]?.instance.raiseEvent(named: event) ?? false
    }

    /// A token answered through `onWaitFinished` when the graph fires `event`.
    /// Nil when the object runs no graph, so the caller can fall back.
    public func awaitEvent(_ event: String, on reference: UInt32) -> UInt64? {
        guard running[reference] != nil else { return nil }
        let token = nextToken
        nextToken += 1
        waits[reference, default: []].append(Wait(event: event, token: token))
        return token
    }

    public func hasGraph(_ reference: UInt32) -> Bool {
        running[reference] != nil
    }

    /// One row per running object, in reference order.
    public var rows: [ObjectAnimationRow] {
        running.keys.sorted().compactMap { reference in
            guard let entry = running[reference] else { return nil }
            return ObjectAnimationRow(
                reference: reference,
                project: entry.object.asset.projectPath,
                events: entry.object.asset.eventNames,
                activeState: entry.instance.activeStates.last?.stateName
            )
        }
    }

    private func start(_ object: CellAnimatedObject) -> Running {
        var load: @Sendable (String) throws -> SplineBehaviorClip = { path in
            throw ObjectBehaviorAssetError.missing(path)
        }
        if let files {
            load = InstallBehaviorClipSource.load(fileSystem: files)
        }
        let worker = SerialAssetLoadWorker<String, SplineBehaviorClip>(load: load)
        let clips = InstallBehaviorClipSource(paths: object.asset.clipPaths, worker: worker)
        // An object never walks: bone 0 is a blade or a door leaf, so no bone is
        // the root whose travel is taken out of the pose.
        let instance = BehaviorGraphInstance(
            graph: object.asset.behavior,
            in: object.asset.objectGraph,
            skeleton: BehaviorSkeleton(object.asset.skeleton, rootBoneIndex: -1),
            clips: clips
        )
        instance.activate()
        instance.prefetchReachableClips()
        return Running(object: object, instance: instance, clips: clips)
    }

    private func finishWaits(on reference: UInt32, event: String) {
        guard var pending = waits[reference] else { return }
        let done = pending.filter { $0.event.caseInsensitiveCompare(event) == .orderedSame }
        pending.removeAll { $0.event.caseInsensitiveCompare(event) == .orderedSame }
        waits[reference] = pending.isEmpty ? nil : pending
        for wait in done {
            onWaitFinished?(wait.token, true)
        }
    }
}
