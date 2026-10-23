// Named nodes of a reference's model, for Papyrus `HasNode` and `MoveToNode`. A model
// loads off the main actor; a call that finds it still loading waits on a token, which
// is answered once the model is in. The rest pose is used: animated nodes do not move.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
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
    let then: (SIMD3<Float>?) -> PapyrusValue
    var answer: PapyrusValue?
}

extension ScriptWorldAdapter {
    func wireModelNodes(provider: WorldDataStores, gameSession: GameSession) {
        guard let files = provider.scriptFileSystem else { return }
        let nodes = AssetLoader<String, [String: SIMD3<Float>]> { path in
            try Self.nodeOrigins(in: NIFFile(data: files.contents(forPath: path)))
        }
        modelNodes = nodes
        gameSession.assetDrains.register(.modelNodes) { [weak self] _ in
            nodes.drain()
            self?.answerNodeWaits()
        }
    }

    func nodePosition(
        of key: ReferenceKey, named name: String,
        nodes: AssetLoader<String, [String: SIMD3<Float>]>,
        then: @escaping (SIMD3<Float>?) -> PapyrusValue
    ) -> PapyrusNodeAnswer {
        guard
            let path = game.streamer?.placedRecords?.baseModelPath(for: key),
            let state = game.scripts.bridge?.referenceState(for: key)
        else { return .missing }
        let toWorld = MatrixMath.placement(
            position: state.transform.position, rotation: state.transform.rotation,
            scale: state.transform.scale
        )
        switch nodes.state(of: path) {
        case let .ready(origins):
            return Self.world(origins[name.lowercased()], toWorld).map { .found($0) } ?? .missing
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

    /// Runs each waiting lookup whose model is in, then hands its answer to the
    /// scheduler, which takes it once the waiting call is queued.
    private func answerNodeWaits() {
        guard let nodes = modelNodes, !nodeWaits.isEmpty else { return }
        for index in nodeWaits.indices where nodeWaits[index].answer == nil {
            let wait = nodeWaits[index]
            switch nodes.state(of: wait.path) {
            case let .ready(origins):
                nodeWaits[index].answer = wait.then(Self.world(origins[wait.node], wait.toWorld))
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

    private static func world(_ local: SIMD3<Float>?, _ toWorld: float4x4) -> SIMD3<Float>? {
        guard let local else { return nil }
        let point = toWorld * SIMD4(local, 1)
        return SIMD3(point.x, point.y, point.z)
    }

    nonisolated private static func nodeOrigins(in file: NIFFile) throws -> [String: SIMD3<Float>] {
        let scene = try NIFEffectScene(file: file)
        var origins: [String: SIMD3<Float>] = [:]
        for (index, node) in scene.nodes.enumerated() {
            guard let name = node.name?.lowercased(), origins[name] == nil else { continue }
            let transform = scene.modelTransform(of: index) { scene.restTransform(of: $0) }
            origins[name] = SIMD3(
                transform.columns.3.x,
                transform.columns.3.y,
                transform.columns.3.z
            )
        }
        return origins
    }
}
