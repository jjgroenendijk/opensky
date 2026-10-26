// Runs the behaviour graph an effect's art model or a worn armour addon names, and passes
// the actor's animation events on to it. A hand or shout effect waits for the actor's
// release event this way. See docs/engine/effect-graphs.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData

/// What the effect graph coordinator reads from the session.
@MainActor
public protocol EffectGraphWorld: AnyObject {
    /// Every live effect that draws an art model, and every worn armour addon model.
    func attachedSubGraphs() -> [AttachedSubGraph]
    /// The actor as its sub-graphs read it; nil when the actor is not loaded.
    func character(of actor: ReferenceKey) -> SubGraphCharacter?
    /// Each event a sub-graph fires, with the actor it is on.
    func effectGraphFired(_ event: String, from actor: ReferenceKey)
}

/// One line of the effect graph readout.
nonisolated public struct EffectGraphRow: Equatable, Sendable {
    public let id: SubGraphID
    public let anchor: SubGraphAnchor
    public let name: String
    public let project: String
    public let activeState: String?
    /// The last actor event the graph declares and so took; nil before the first.
    public let lastEvent: String?
    public let takenCount: Int

    public var actor: ReferenceKey? {
        guard case let .actor(key) = anchor else { return nil }
        return key
    }
}

@MainActor
public final class EffectGraphCoordinator {
    final class Running {
        let attachment: AttachedSubGraph
        let project: String
        let instance: BehaviorGraphInstance
        var lastEvent: String?
        var takenCount = 0
        /// The graph's newest pose, in the bone order of `skeleton`.
        var bones: [HKABonePose] = []
        /// Lower-case names a script set, which the actor's own values no longer overwrite.
        var scriptHeld: Set<String> = []
        /// The actor's rig as the last step read it, and the bones this graph moves on it.
        var actorRig: SubGraphActorRig?
        var boneMap: SubGraphBoneMap?

        init(attachment: AttachedSubGraph, project: String, instance: BehaviorGraphInstance) {
            self.attachment = attachment
            self.project = project
            self.instance = instance
        }
    }

    enum ModelState {
        case loading
        case ready(EffectGraphProject)
        /// The model names no graph, or its graph failed to load.
        case noGraph
    }

    weak let world: (any EffectGraphWorld)?
    /// A closure, because the install is chosen after the app builds this coordinator.
    private let files: () -> (any GameFileSource)?
    private var loader: SerialAssetLoadWorker<String, LoadedEffectGraphProject?>?
    private(set) var models: [String: ModelState] = [:]
    private(set) var running: [SubGraphID: Running] = [:]
    /// The pose buffers an armour addon graph moved at the last step, by actor.
    var overlaidPoses: [ReferenceKey: PlayerPoseBuffer] = [:]
    /// Off stops every effect graph; the effects still draw.
    public var isEnabled = true {
        didSet {
            if !isEnabled {
                running.removeAll()
            }
        }
    }

    public init(world: any EffectGraphWorld, files: @escaping () -> (any GameFileSource)?) {
        self.world = world
        self.files = files
    }

    /// Sends an actor's event to every sub-graph on that actor, in sub-graph order. A
    /// graph that does not declare the event ignores it. True when a graph took it.
    @discardableResult
    public func deliver(_ event: String, from actor: ReferenceKey) -> Bool {
        var taken = false
        for entry in graphs(on: actor) where entry.instance.raiseEvent(named: event) {
            entry.lastEvent = event
            entry.takenCount += 1
            taken = true
        }
        return taken
    }

    /// `Actor.SetSubGraphFloatVariable`: sets the variable on every sub-graph of the actor
    /// that declares it. True when one did.
    @discardableResult
    public func setSubGraphVariable(_ value: Float, named name: String, on actor: ReferenceKey)
        -> Bool
    {
        var taken = false
        for entry in graphs(on: actor)
            where entry.instance.setVariable(.real(value), named: name)
        {
            entry.scriptHeld.insert(name.lowercased())
            taken = true
        }
        return taken
    }

    public func hasSubGraphs(on actor: ReferenceKey) -> Bool {
        running.values.contains { $0.attachment.actor == actor }
    }

    private func graphs(on actor: ReferenceKey) -> [Running] {
        running.keys.sorted().compactMap { id in
            running[id].flatMap { $0.attachment.actor == actor ? $0 : nil }
        }
    }

    /// Takes finished loads, starts graphs for new effects, drops ended ones, and steps
    /// each graph in effect order.
    public func tick(deltaTime: Float) {
        drainLoads()
        guard isEnabled, let world else { return }
        sync(world.attachedSubGraphs())
        for case let .ready(project) in models.values {
            project.clips.drain()
        }
        guard deltaTime > 0 else { return }
        for id in running.keys.sorted() {
            guard let entry = running[id] else { continue }
            prepare(entry, world: world)
            let result = entry.instance.update(deltaTime: deltaTime)
            if !result.bones.isEmpty {
                entry.bones = result.bones
            }
            guard let actor = entry.attachment.actor else { continue }
            for name in result.firedEvents.compactMap(\.name) + result.unboundEvents {
                world.effectGraphFired(name, from: actor)
            }
        }
        poseArmorAddons()
    }

    /// Runs an activated graph for one model, such as a test's synthetic one.
    func start(
        _ attachment: AttachedSubGraph, project: String, instance: BehaviorGraphInstance
    ) {
        running[attachment.id] = Running(
            attachment: attachment, project: project, instance: instance
        )
    }

    /// The rig an effect model's graph poses: nil while the model loads, which this starts,
    /// and `.some(nil)` when the model names no graph.
    public func graphSkeleton(forModel path: String) -> HKASkeleton?? {
        if let project = project(forModel: path) {
            return .some(project.asset.skeleton)
        }
        if case .noGraph = models[path] {
            return .some(nil)
        }
        return nil
    }

    /// The newest pose of an effect's graph, in the bone order of its model's rig.
    public func pose(ofEffect id: Int) -> [HKABonePose] {
        running[.effect(id)]?.bones ?? []
    }

    /// One row per running sub-graph, in sub-graph order.
    public var rows: [EffectGraphRow] {
        running.keys.sorted().compactMap { id in
            guard let entry = running[id] else { return nil }
            return EffectGraphRow(
                id: id, anchor: entry.attachment.anchor,
                name: entry.attachment.name, project: entry.project,
                activeState: entry.instance.activeStates.last?.stateName,
                lastEvent: entry.lastEvent, takenCount: entry.takenCount
            )
        }
    }

    private func sync(_ attached: [AttachedSubGraph]) {
        var seen = Set<SubGraphID>()
        for attachment in attached {
            seen.insert(attachment.id)
            guard
                running[attachment.id] == nil,
                let project = project(forModel: attachment.modelPath) else { continue }
            start(attachment, project: project.asset.projectPath, instance: project.instance())
        }
        for id in running.keys where !seen.contains(id) {
            running.removeValue(forKey: id)?.instance.deactivate()
        }
    }

    // MARK: - Loading

    /// The ready project of a model, or nil while it loads or when it names none.
    private func project(forModel path: String) -> EffectGraphProject? {
        switch models[path] {
        case let .ready(project): return project
        case .loading, .noGraph: return nil
        case nil:
            guard let loader = modelLoader() else { return nil }
            models[path] = .loading
            loader.submit(path, priority: .needed)
            return nil
        }
    }

    private func modelLoader() -> SerialAssetLoadWorker<String, LoadedEffectGraphProject?>? {
        if let loader {
            return loader
        }
        guard let files = files() else { return nil }
        let loader = SerialAssetLoadWorker<String, LoadedEffectGraphProject?>(
            queue: AssetLoadQueue.background, load: LoadedEffectGraphProject.load(files)
        )
        self.loader = loader
        return loader
    }

    private func drainLoads() {
        guard let loader, let files = files() else { return }
        for completion in loader.takeFinished() {
            switch completion.result {
            case let .success(loaded?):
                models[completion.key] = .ready(EffectGraphProject(loaded, files: files))
            case .success(nil), .failure:
                models[completion.key] = .noGraph
            }
        }
    }
}
