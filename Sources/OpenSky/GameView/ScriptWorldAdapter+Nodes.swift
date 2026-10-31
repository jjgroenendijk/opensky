// Named nodes of a reference's 3D, for Papyrus `HasNode`, `MoveToNode`, and
// `PlayImpactEffect`: an actor's posed skeleton, a running object graph's posed bones,
// else the base model's rest pose. A model loads off the main actor; a call that finds
// it still loading waits on a token, which is answered once the model is in.

import Foundation
import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// One node lookup that waits for its model.
struct ModelNodeWait {
    /// Above the menu and object-animation token ranges.
    static let firstToken: UInt64 = 1 << 52

    let token: UInt64
    let path: String
    let node: String
    let toWorld: float4x4
    let then: (simd_float4x4?) -> PapyrusValue
    var answer: PapyrusValue?
}

extension ScriptWorldAdapter {
    func wireModelNodes(provider: WorldDataStores, gameSession: GameSession) {
        guard let files = provider.scriptFileSystem else { return }
        let nodes = AssetLoader<String, [String: PosedBone]> { path in
            try Self.nodeTransforms(in: NIFFile(data: files.contents(forPath: path)))
        }
        modelNodes = nodes
        gameSession.assetDrains.register(.modelNodes) { [weak self] _ in
            nodes.drain()
            self?.answerNodeWaits()
        }
    }

    func nodeTransform(
        of key: ReferenceKey, named name: String,
        nodes: AssetLoader<String, [String: PosedBone]>,
        then: @escaping (simd_float4x4?) -> PapyrusValue
    ) -> PapyrusNodeAnswer {
        guard let state = game.scripts.bridge?.referenceState(for: key) else { return .missing }
        let toWorld = MatrixMath.placement(
            position: state.transform.position, rotation: state.transform.rotation,
            scale: state.transform.scale
        )
        if let posed = posedNode(of: key, named: name) {
            return .found(toWorld * posed.model)
        }
        guard let path = game.streamer?.placedRecords?.baseModelPath(for: key) else {
            return .missing
        }
        switch nodes.state(of: path) {
        case let .ready(transforms):
            return transforms[name.lowercased()].map { .found(toWorld * $0.model) } ?? .missing
        case .failed:
            return .missing
        case .loading:
            let token = nextNodeToken
            nextNodeToken += 1
            nodeWaits.append(ModelNodeWait(
                token: token, path: path, node: name.lowercased(), toWorld: toWorld, then: then
            ))
            return .loading(token: token)
        }
    }

    /// A node inside its parent node and in the world, if it can be read now.
    func readyNode(
        of key: ReferenceKey, named name: String
    ) -> (local: simd_float4x4, world: simd_float4x4)? {
        guard let state = game.scripts.bridge?.referenceState(for: key) else { return nil }
        let toWorld = MatrixMath.placement(
            position: state.transform.position, rotation: state.transform.rotation,
            scale: state.transform.scale
        )
        if let posed = posedNode(of: key, named: name) {
            return (posed.local, toWorld * posed.model)
        }
        guard
            let path = game.streamer?.placedRecords?.baseModelPath(for: key),
            case let .ready(transforms)? = modelNodes?.state(of: path),
            let rest = transforms[name.lowercased()]
        else { return nil }
        return (rest.local, toWorld * rest.model)
    }

    /// A node that moves now, in the reference's own space: a bone of the actor's
    /// skeleton, or of the object graph it runs.
    private func posedNode(of key: ReferenceKey, named name: String) -> PosedBone? {
        if
            let renderer = game.renderer, let playback = game.actorPlayback(for: key),
            let pose = playback.skeletonPose(at: renderer.animationTime),
            let index = pose.bones.index(of: name),
            let bone = PosedBone(
                index: index,
                matrices: pose.matrices,
                parents: playback.clip.skeleton.parentIndices
            )
        {
            return bone
        }
        guard let formID = game.streamer?.referenceEntry(key: key)?.formID else { return nil }
        return game.objectAnimationWorld.objects.bone(of: formID.rawValue, named: name)
    }

    /// Runs each waiting lookup whose model is in, then hands its answer to the
    /// scheduler, which takes it once the waiting call is queued.
    private func answerNodeWaits() {
        guard let nodes = modelNodes, !nodeWaits.isEmpty else { return }
        for index in nodeWaits.indices where nodeWaits[index].answer == nil {
            let wait = nodeWaits[index]
            switch nodes.state(of: wait.path) {
            case let .ready(transforms):
                nodeWaits[index].answer = wait.then(
                    transforms[wait.node].map { wait.toWorld * $0.model }
                )
            case .failed:
                nodeWaits[index].answer = wait.then(nil)
            case .loading:
                continue
            }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        nodeWaits.removeAll { wait in
            guard let answer = wait.answer else { return false }
            return scheduler.answer(wait.token, returning: answer)
        }
    }

    nonisolated private static func nodeTransforms(
        in file: NIFFile
    ) throws -> [String: PosedBone] {
        let scene = try NIFEffectScene(file: file)
        var transforms: [String: PosedBone] = [:]
        for (index, node) in scene.nodes.enumerated() {
            guard let name = node.name?.lowercased(), transforms[name] == nil else { continue }
            transforms[name] = PosedBone(
                model: scene.modelTransform(of: index) { scene.restTransform(of: $0) },
                local: scene.restTransform(of: index)
            )
        }
        return transforms
    }
}
