// Runs the behaviour graph an effect's art model names, for each effect on an actor, and
// passes the actor's animation events on to it. A hand or shout effect waits for the
// actor's release event this way. See docs/engine/effect-graphs.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One live effect on an actor that draws an art model.
nonisolated public struct AttachedEffectModel: Equatable, Sendable {
    public let effectID: Int
    public let actor: ReferenceKey
    public let effectName: String
    public let modelPath: String

    public init(effectID: Int, actor: ReferenceKey, effectName: String, modelPath: String) {
        self.effectID = effectID
        self.actor = actor
        self.effectName = effectName
        self.modelPath = modelPath
    }
}

/// What the effect graph coordinator reads from the session.
@MainActor
public protocol EffectGraphWorld: AnyObject {
    /// Every live effect on a loaded actor that draws an art model.
    func attachedEffectModels() -> [AttachedEffectModel]
    /// Each event an effect graph fires, with the actor it is on.
    func effectGraphFired(_ event: String, from actor: ReferenceKey)
}

/// One line of the effect graph readout.
nonisolated public struct EffectGraphRow: Equatable, Sendable {
    public let effectID: Int
    public let actor: ReferenceKey
    public let effectName: String
    public let project: String
    public let activeState: String?
    /// The last actor event the graph declares and so took; nil before the first.
    public let lastEvent: String?
    public let takenCount: Int
}

@MainActor
public final class EffectGraphCoordinator {
    final class Running {
        let attachment: AttachedEffectModel
        let project: String
        let instance: BehaviorGraphInstance
        var lastEvent: String?
        var takenCount = 0
        /// The graph's newest pose, in the bone order of `skeleton`.
        var bones: [HKABonePose] = []

        init(attachment: AttachedEffectModel, project: String, instance: BehaviorGraphInstance) {
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
    private(set) var running: [Int: Running] = [:]
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

    /// Sends an actor's event to every graph of an effect on that actor, in effect order.
    /// A graph that does not declare the event ignores it.
    public func deliver(_ event: String, from actor: ReferenceKey) {
        for id in running.keys.sorted() {
            guard let entry = running[id], entry.attachment.actor == actor else { continue }
            if entry.instance.raiseEvent(named: event) {
                entry.lastEvent = event
                entry.takenCount += 1
            }
        }
    }

    /// Takes finished loads, starts graphs for new effects, drops ended ones, and steps
    /// each graph in effect order.
    public func tick(deltaTime: Float) {
        drainLoads()
        guard isEnabled, let world else { return }
        sync(world.attachedEffectModels())
        for case let .ready(project) in models.values {
            project.clips.drain()
        }
        guard deltaTime > 0 else { return }
        for id in running.keys.sorted() {
            guard let entry = running[id] else { continue }
            let result = entry.instance.update(deltaTime: deltaTime)
            if !result.bones.isEmpty {
                entry.bones = result.bones
            }
            for name in result.firedEvents.compactMap(\.name) + result.unboundEvents {
                world.effectGraphFired(name, from: entry.attachment.actor)
            }
        }
    }

    /// Runs an activated graph for one effect, such as a test's synthetic one.
    func start(
        _ attachment: AttachedEffectModel, project: String, instance: BehaviorGraphInstance
    ) {
        running[attachment.effectID] = Running(
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
        running[id]?.bones ?? []
    }

    /// One row per running effect graph, in effect order.
    public var rows: [EffectGraphRow] {
        running.keys.sorted().compactMap { id in
            guard let entry = running[id] else { return nil }
            return EffectGraphRow(
                effectID: id, actor: entry.attachment.actor,
                effectName: entry.attachment.effectName, project: entry.project,
                activeState: entry.instance.activeStates.last?.stateName,
                lastEvent: entry.lastEvent, takenCount: entry.takenCount
            )
        }
    }

    private func sync(_ attached: [AttachedEffectModel]) {
        var seen = Set<Int>()
        for attachment in attached {
            seen.insert(attachment.effectID)
            guard
                running[attachment.effectID] == nil,
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
