// Runs the behaviour graph of each loaded NPC and creature, as the player's runs. The
// race names the graph project; one decode per project is shared by every actor of
// it. The rules live in `ActorGraphCore`. See docs/engine/actor-graphs.md.

import Foundation
import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One loaded actor that can run a graph.
nonisolated public struct ActorGraphCandidate: Equatable, Sendable {
    public let key: ReferenceKey
    /// The race's behaviour graph project, as an archive path.
    public let projectPath: String
    public let feet: SIMD3<Float>
    /// The placement's Z rotation.
    public let rotationZ: Float

    public init(key: ReferenceKey, projectPath: String, feet: SIMD3<Float>, rotationZ: Float) {
        self.key = key
        self.projectPath = projectPath
        self.feet = feet
        self.rotationZ = rotationZ
    }
}

/// What the actor graph coordinator reads from the session.
@MainActor
public protocol ActorGraphWorld: AnyObject {
    /// Every loaded, living actor whose race names a graph.
    func actorGraphCandidates() -> [ActorGraphCandidate]
    /// Where the cutoff distance is measured from. Nil steps every graph at full rate.
    var actorGraphViewer: SIMD3<Float>? { get }
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback?
}

/// A project decoded off the main actor, with its behaviour folder indexed.
nonisolated struct LoadedActorGraphProject: Sendable {
    let asset: BehaviorProjectAsset
    let referencePaths: [String: String]

    static func load(_ files: any GameFileSource) -> @Sendable (String) throws -> Self {
        { path in
            let asset = try BehaviorProjectAsset.load(
                fileSystem: files, projectPath: path, folderClips: true
            )
            let references = InstallBehaviorReferenceSource.index(
                files, rootPath: asset.behaviorPath
            )
            return Self(asset: asset, referencePaths: references)
        }
    }
}

@MainActor
public final class ActorGraphCoordinator {
    /// One project's shared decode, clips, and behaviour references.
    final class Project {
        let asset: BehaviorProjectAsset
        let clips: InstallBehaviorClipSource
        let references: InstallBehaviorReferenceSource
        let skeleton: BehaviorSkeleton
        /// One decode of the graph file for every actor of the race.
        let objects: SharedBehaviorObjectSource
        /// Every actor of the race reaches the same clips, so the first one asks for them.
        var hasPrefetched = false

        init(_ loaded: LoadedActorGraphProject, files: any GameFileSource) {
            asset = loaded.asset
            objects = SharedBehaviorObjectSource(graph: loaded.asset.objectGraph)
            let worker = SerialAssetLoadWorker<String, SplineBehaviorClip>(
                queue: AssetLoadQueue.background,
                load: InstallBehaviorClipSource.load(fileSystem: files)
            )
            clips = InstallBehaviorClipSource(paths: loaded.asset.clipPaths, worker: worker)
            references = InstallBehaviorReferenceSource(
                fileSystem: files, pathsByName: loaded.referencePaths
            )
            skeleton = BehaviorSkeleton(loaded.asset.skeleton)
        }
    }

    enum ProjectState {
        case loading
        case ready(Project)
        case failed(String)
    }

    final class Running {
        let project: Project
        let instance: BehaviorGraphInstance
        let pose = PlayerPoseBuffer()
        weak var playback: ActorAnimationPlayback?
        var motion = ActorGraphMotion.still
        var pendingEvents: [String] = []
        var lastFeet: SIMD3<Float>?
        var lastRotation: Float?
        var sinceStep: Float = 0
        var steps = 0
        var rate = ActorGraphStepRate.full
        var recentEvents: [String] = []
        /// The player's mount drive steps this graph while it is lent.
        var isLent = false

        init(project: Project, instance: BehaviorGraphInstance) {
            self.project = project
            self.instance = instance
        }
    }

    /// How many fired events the readout keeps per actor.
    public static let recentEventLimit = 12
    /// Papyrus message tokens start at 1 and object graph waits at 2^48; actor waits
    /// use the range above both.
    public static let firstToken: UInt64 = 1 << 56

    weak let world: (any ActorGraphWorld)?
    /// A closure, because the install is chosen after the app builds this coordinator.
    private let files: () -> (any GameFileSource)?
    private var loader: SerialAssetLoadWorker<String, LoadedActorGraphProject>?
    var projects: [String: ProjectState] = [:]
    private(set) var running: [ReferenceKey: Running] = [:]
    /// Drive changes that arrived before the actor's graph started.
    var motions: [ReferenceKey: ActorGraphMotion] = [:]
    private(set) var fullRateCount = 0
    private(set) var reducedRateCount = 0

    /// Off returns every actor to its clips.
    public var isEnabled = true {
        didSet {
            if !isEnabled {
                stopAll()
            }
        }
    }

    public var cutoff = ActorGraphCutoff.standard
    /// Each event a graph fires, by actor, in fire order.
    public var onAnimationEvent: ((ReferenceKey, String) -> Void)?
    /// A wait that finished, by its token; true when its event fired.
    public var onWaitFinished: ((UInt64, Bool) -> Void)?
    private var waits: [ReferenceKey: [(event: String, token: UInt64)]] = [:]
    private var nextToken = firstToken

    public init(world: any ActorGraphWorld, files: @escaping () -> (any GameFileSource)?) {
        self.world = world
        self.files = files
    }

    /// Takes finished project loads, starts graphs for new actors, drops departed ones,
    /// and steps each graph the cutoff allows, in key order.
    public func tick(deltaTime: Float) {
        drainProjects()
        fullRateCount = 0
        reducedRateCount = 0
        guard isEnabled, let world else { return }
        let candidates = world.actorGraphCandidates().sorted { $0.key < $1.key }
        sync(candidates, world: world)
        for case let .ready(project) in projects.values {
            project.clips.drain()
        }
        guard deltaTime > 0 else { return }
        let viewer = world.actorGraphViewer
        for candidate in candidates {
            guard let entry = running[candidate.key], !entry.isLent else { continue }
            let distance = viewer.map { simd_distance($0, candidate.feet) } ?? 0
            guard let interval = cutoff.stepInterval(atDistance: distance) else {
                entry.rate = .stopped
                entry.sinceStep = 0
                continue
            }
            entry.rate = interval == 0 ? .full : .reduced
            entry.sinceStep += deltaTime
            guard entry.sinceStep >= interval else { continue }
            step(entry, candidate, actor: candidate.key)
            entry.sinceStep = 0
            if interval == 0 {
                fullRateCount += 1
            } else {
                reducedRateCount += 1
            }
        }
    }

    /// A token answered through `onWaitFinished` when the actor's graph fires `event`.
    /// Nil when the actor runs no graph, so the caller can fall back.
    public func awaitEvent(_ event: String, on actor: ReferenceKey) -> UInt64? {
        guard running[actor] != nil else { return nil }
        let token = nextToken
        nextToken += 1
        waits[actor, default: []].append((event, token))
        return token
    }

    // MARK: - Starting and stopping

    private func sync(_ candidates: [ActorGraphCandidate], world: any ActorGraphWorld) {
        var seen = Set<ReferenceKey>()
        for candidate in candidates {
            seen.insert(candidate.key)
            let playback = world.actorPlayback(for: candidate.key)
            if let entry = running[candidate.key] {
                if entry.playback !== playback {
                    // A rebuilt cell brings a new playback; the graph keeps running.
                    entry.playback = playback
                    playback?.attachGraph(skeleton: entry.project.asset.skeleton, pose: entry.pose)
                }
                continue
            }
            guard let playback, let project = project(at: candidate.projectPath) else {
                continue
            }
            running[candidate.key] = start(project, on: playback, actor: candidate.key)
        }
        for key in running.keys where !seen.contains(key) {
            stop(key)
        }
    }

    private func start(
        _ project: Project, on playback: ActorAnimationPlayback, actor: ReferenceKey
    ) -> Running {
        let instance = BehaviorGraphInstance(
            graph: project.asset.behavior, in: project.asset.objectGraph,
            skeleton: project.skeleton, clips: project.clips, objects: project.objects
        )
        instance.references = project.references
        instance.activate()
        if !project.hasPrefetched {
            project.hasPrefetched = true
            instance.prefetchReachableClips()
        }
        let entry = Running(project: project, instance: instance)
        entry.playback = playback
        entry.motion = motions[actor] ?? .still
        entry.pendingEvents = ActorGraphCore.events(from: .still, to: entry.motion)
        playback.attachGraph(skeleton: project.asset.skeleton, pose: entry.pose)
        return entry
    }

    private func stop(_ actor: ReferenceKey) {
        guard let entry = running.removeValue(forKey: actor) else { return }
        entry.instance.deactivate()
        entry.playback?.detachGraph()
        for wait in waits.removeValue(forKey: actor) ?? [] {
            onWaitFinished?(wait.token, false)
        }
    }

    private func stopAll() {
        for key in running.keys.sorted() {
            stop(key)
        }
    }

    // MARK: - Stepping

    private func step(_ entry: Running, _ candidate: ActorGraphCandidate, actor: ReferenceKey) {
        let seconds = entry.sinceStep
        let input = ActorGraphStepInput(
            motion: entry.motion,
            speed: entry.lastFeet.map {
                ActorGraphCore.speed(from: $0, to: candidate.feet, seconds: seconds)
            } ?? 0,
            turnDelta: entry.lastRotation.map {
                // Placement rotation turns clockwise; the graph's turn is counter-clockwise.
                -ActorGraphCore.turnDelta(from: $0, to: candidate.rotationZ)
            } ?? 0,
            deltaTime: seconds
        )
        entry.lastFeet = candidate.feet
        entry.lastRotation = candidate.rotationZ
        let instance = entry.instance
        for (name, value) in ActorGraphCore.variables(input) {
            instance.setVariable(value, named: name)
        }
        instance.characterContext = BehaviorCharacterContext(
            worldPosition: candidate.feet,
            worldRotation: ActorGraphCore.worldRotation(placementRotationZ: candidate.rotationZ)
        )
        for event in entry.pendingEvents {
            instance.raiseEvent(named: event)
        }
        entry.pendingEvents = []
        let result = instance.update(deltaTime: seconds)
        entry.steps += 1
        if !result.bones.isEmpty {
            entry.pose.publish(result.bones)
        }
        report(result.firedEvents.compactMap(\.name) + result.unboundEvents, from: actor)
    }

    /// Sends the events an actor's graph fired to the readout, the listeners, and the waits.
    public func report(_ names: [String], from actor: ReferenceKey) {
        guard !names.isEmpty, let entry = running[actor] else { return }
        entry.recentEvents = Array((entry.recentEvents + names).suffix(Self.recentEventLimit))
        for name in names {
            onAnimationEvent?(actor, name)
            finishWaits(on: actor, event: name)
        }
    }

    private func finishWaits(on actor: ReferenceKey, event: String) {
        guard let pending = waits[actor] else { return }
        let matches = { (wait: (event: String, token: UInt64)) in
            wait.event.caseInsensitiveCompare(event) == .orderedSame
        }
        let left = pending.filter { !matches($0) }
        waits[actor] = left.isEmpty ? nil : left
        for wait in pending where matches(wait) {
            onWaitFinished?(wait.token, true)
        }
    }

    // MARK: - Projects

    /// The ready project, or nil while it loads or after it failed.
    private func project(at path: String) -> Project? {
        switch projects[path] {
        case let .ready(project): return project
        case .loading, .failed: return nil
        case nil:
            guard let loader = projectLoader() else { return nil }
            projects[path] = .loading
            loader.submit(path, priority: .needed)
            return nil
        }
    }

    private func projectLoader() -> SerialAssetLoadWorker<String, LoadedActorGraphProject>? {
        if let loader {
            return loader
        }
        guard let files = files() else { return nil }
        let loader = SerialAssetLoadWorker<String, LoadedActorGraphProject>(
            queue: AssetLoadQueue.background, load: LoadedActorGraphProject.load(files)
        )
        self.loader = loader
        return loader
    }

    private func drainProjects() {
        guard let loader, let files = files() else { return }
        for completion in loader.takeFinished() {
            switch completion.result {
            case let .success(loaded):
                projects[completion.key] = .ready(Project(loaded, files: files))
            case let .failure(failure):
                projects[completion.key] = .failed(failure.reason)
            }
        }
    }
}

/// A running graph's variables, as a condition reads them.
nonisolated struct ActorGraphVariables: GraphVariableReading {
    let store: BehaviorVariableStore

    func graphVariableInt(_ name: String) -> Int? {
        store.value(of: name)?.intValue
    }

    func graphVariableFloat(_ name: String) -> Float? {
        store.value(of: name)?.realValue
    }
}
