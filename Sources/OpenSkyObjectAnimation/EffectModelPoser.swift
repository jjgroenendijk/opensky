// Poses each effect model whose nodes move: by its own controllers, such as the lag bone
// of a magic beam, and by its effect graph. Each such effect draws a node-skinned copy
// from a pool per model. See docs/rendering/visual-effects.md#posed-effect-models.

import Foundation
import OpenSkyActorPresentation
public import OpenSkyEffects
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyWorldInterface
import simd

/// The node controllers of an effect model, read off the main actor.
nonisolated struct LoadedEffectNodes: Sendable {
    let rig: NodeControllerRig?

    static func load(_ files: any GameFileSource) -> @Sendable (String) throws -> Self {
        { path in
            let file = try NIFFile(data: files.contents(forPath: EffectModelPoser.meshKey(path)))
            let lagOnly = NIFBehaviorGraphExtraData.projectPath(in: file) != nil
            return try Self(rig: NodeControllerRig(file: file, lagOnly: lagOnly))
        }
    }
}

@MainActor
public final class EffectModelPoser: EffectModelPosing {
    /// A posed copy of one model, kept for the next effect of that model when its effect ends.
    final class Copy {
        let model: RenderModel
        let pose = PlayerPoseBuffer()
        let playback: PlayerAnimationPlayback

        init(model: RenderModel, skeleton: HKASkeleton) {
            self.model = model
            playback = PlayerAnimationPlayback(skeleton: skeleton, pose: pose, models: [model])
        }
    }

    final class Running {
        let path: String
        let rig: EffectPoseRig
        let copy: Copy
        var animator: NIFNodeAnimator?

        init(path: String, rig: EffectPoseRig, copy: Copy) {
            self.path = path
            self.rig = rig
            self.copy = copy
            animator = rig.nodes.map { NIFNodeAnimator(animation: $0.animation) }
        }
    }

    enum RigState {
        case loading
        case ready(NodeControllerRig?)
    }

    private let files: () -> (any GameFileSource)?
    private let meshes: () -> MeshLibrary?
    private let graphs: EffectGraphCoordinator
    /// The camera billboards turn to; nil leaves them at rest.
    private let viewer: () -> NIFBillboard.Viewer?
    private var loader: SerialAssetLoadWorker<String, LoadedEffectNodes>?
    private var nodeRigs: [String: RigState] = [:]
    /// The merged rig of each model; nil inside records a model that does not move.
    private var poseRigs: [String: EffectPoseRig?] = [:]
    private var running: [Int: Running] = [:]
    private var spare: [String: [Copy]] = [:]
    private var nextCopy: UInt32 = 0
    /// Off draws every effect model as authored.
    public var isEnabled = true

    public init(
        files: @escaping () -> (any GameFileSource)?,
        meshes: @escaping () -> MeshLibrary?,
        graphs: EffectGraphCoordinator,
        viewer: @escaping () -> NIFBillboard.Viewer? = { nil }
    ) {
        self.files = files
        self.meshes = meshes
        self.graphs = graphs
        self.viewer = viewer
    }

    public func pose(_ models: [VisualEffectModel], deltaTime: Float) -> [Int: PosedEffectModel] {
        drainLoads()
        guard isEnabled else {
            release(Set(running.keys))
            return [:]
        }
        var posed: [Int: PosedEffectModel] = [:]
        var seen = Set<Int>()
        let camera = viewer()
        for model in models {
            guard
                let id = model.instanceID, seen.insert(id).inserted,
                let entry = running[id] ?? start(
                    id,
                    path: model.path
                ) else { continue }
            entry.animator?.step(
                deltaTime: deltaTime,
                placement: NodeControllerCoordinator.transform(model.transform)
            )
            if let camera {
                entry.animator?.face(camera.local(to: model.transform))
            }
            let bones = entry.rig.bonePoses(
                graph: graphs.pose(ofEffect: id),
                animator: entry.animator
            )
            entry.copy.pose.publish(bones)
            posed[id] = PosedEffectModel(
                model: entry.copy.model, animation: entry.copy.playback,
                nodeDeltas: entry.rig.nodeDeltas(bones)
            )
        }
        release(Set(running.keys).subtracting(seen))
        return posed
    }

    /// The first sequence the effect's graph plays; a graph plays one per state.
    public func playedSequence(ofEffect id: Int) -> String? {
        graphs.sequences(ofEffect: id).first
    }

    /// One row per posed effect, in effect order.
    public var rows: [PosedEffectRow] {
        running.keys.sorted().compactMap { id in
            running[id].map {
                PosedEffectRow(effectID: id, modelPath: $0.path, bones: $0.rig.skeleton.boneNames)
            }
        }
    }

    nonisolated static func meshKey(_ path: String) -> String {
        let key = path.lowercased().replacingOccurrences(of: "/", with: "\\")
        return key.hasPrefix("meshes\\") ? key : "meshes\\" + key
    }

    private func start(_ id: Int, path: String) -> Running? {
        guard let rig = poseRig(forModel: path), let copy = copy(of: path, rig: rig) else {
            return nil
        }
        let entry = Running(path: path, rig: rig, copy: copy)
        running[id] = entry
        return entry
    }

    private func release(_ ids: Set<Int>) {
        for id in ids.sorted() {
            guard let entry = running.removeValue(forKey: id) else { continue }
            spare[entry.path, default: []].append(entry.copy)
        }
    }

    /// The merged rig once both the node controllers and the graph are known.
    private func poseRig(forModel path: String) -> EffectPoseRig? {
        if let known = poseRigs[path] {
            return known
        }
        guard
            case let .ready(nodes) = nodeRig(forModel: path),
            let graph = graphs.graphSkeleton(forModel: path)
        else { return nil }
        let rig = EffectPoseRig(nodes: nodes, graph: graph)
        poseRigs[path] = .some(rig)
        return rig
    }

    private func copy(of path: String, rig: EffectPoseRig) -> Copy? {
        if let reused = spare[path]?.popLast() {
            return reused
        }
        // Copies take references above every plugin's, so they never meet a placed one.
        let reference = 0xFF00_0000 | nextCopy
        guard
            let meshes = meshes(),
            let model = attempt({
                try meshes.animatedObjectModel(
                    path: path, bones: Set(rig.skeleton.boneNames), reference: reference,
                    surface: ModelSurfaceOverride(
                        diffuseTexture: nil,
                        normalTexture: nil,
                        tint: nil
                    )
                )
            })
        else {
            poseRigs[path] = .some(nil)
            return nil
        }
        nextCopy &+= 1
        return Copy(model: model, skeleton: rig.skeleton)
    }

    private func nodeRig(forModel path: String) -> RigState? {
        if let known = nodeRigs[path] {
            return known
        }
        guard let loader = nodeLoader() else { return nil }
        nodeRigs[path] = .loading
        loader.submit(path, priority: .needed)
        return .loading
    }

    private func nodeLoader() -> SerialAssetLoadWorker<String, LoadedEffectNodes>? {
        if let loader {
            return loader
        }
        guard let files = files() else { return nil }
        let loader = SerialAssetLoadWorker<String, LoadedEffectNodes>(
            queue: AssetLoadQueue.background, load: LoadedEffectNodes.load(files)
        )
        self.loader = loader
        return loader
    }

    private func drainLoads() {
        guard let loader else { return }
        for completion in loader.takeFinished() {
            nodeRigs[completion.key] = .ready(attempt { try completion.result.get() }?.rig)
        }
    }
}
