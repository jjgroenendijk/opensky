import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsAnimation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyObjectAnimation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// One node lookup that waits for its model.
public struct ModelNodeWait {
    /// Above the menu and object-animation token ranges.
    public static let firstToken: UInt64 = 1 << 52

    let token: UInt64
    let path: String
    let node: String
    let toWorld: float4x4
    let then: (simd_float4x4?) -> PapyrusValue
    var answer: PapyrusValue?
}

/// What `ScriptNodeBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptNodeBindingsHost: AnyObject, SendableMetatype {
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var aiWorld: any AIWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var objectAnimationWorld: any ObjectAnimationWorldPort { get }
    var perception: any PerceptionPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptNodeBindingsAdapter {
    public let game: any ScriptNodeBindingsHost
    public let state: ScriptPartState
}

extension ScriptNodeBindingsAdapter {
    public func nodeTransform(
        of key: ReferenceKey, named name: String,
        nodes: AssetLoader<String, [String: PosedBone]>,
        then: @escaping (simd_float4x4?) -> PapyrusValue
    ) -> PapyrusNodeAnswer {
        guard let reference = game.scripts.bridge?.referenceState(for: key) else { return .missing }
        let toWorld = MatrixMath.placement(
            position: reference.transform.position, rotation: reference.transform.rotation,
            scale: reference.transform.scale
        )
        if let posed = posedNode(of: key, named: name) {
            return .found(toWorld * posed.model)
        }
        guard let path = game.streamer.placedRecords?.baseModelPath(for: key) else {
            return .missing
        }
        switch nodes.state(of: path) {
        case let .ready(transforms):
            return transforms[name.lowercased()].map { .found(toWorld * $0.model) } ?? .missing
        case .failed:
            return .missing
        case .loading:
            let token = state.nextNodeToken
            state.nextNodeToken += 1
            state.nodeWaits.append(ModelNodeWait(
                token: token, path: path, node: name.lowercased(), toWorld: toWorld, then: then
            ))
            return .loading(token: token)
        }
    }

    /// A node inside its parent node and in the world, if it can be read now.
    func readyNode(
        of key: ReferenceKey, named name: String
    ) -> (local: simd_float4x4, world: simd_float4x4)? {
        guard let reference = game.scripts.bridge?.referenceState(for: key) else { return nil }
        let toWorld = MatrixMath.placement(
            position: reference.transform.position, rotation: reference.transform.rotation,
            scale: reference.transform.scale
        )
        if let posed = posedNode(of: key, named: name) {
            return (posed.local, toWorld * posed.model)
        }
        guard
            let path = game.streamer.placedRecords?.baseModelPath(for: key),
            case let .ready(transforms)? = state.modelNodes?.state(of: path),
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
        guard let formID = game.streamer.referenceEntry(key: key)?.formID else { return nil }
        return game.objectAnimationWorld.objects.bone(of: formID.rawValue, named: name)
    }

    func answerNodeWaits() {
        ScriptModelNodeLoader(game: game, state: state).answerNodeWaits()
    }

    func sees(
        viewer: ReferenceKey, target: ReferenceKey, bridge: PapyrusWorldStateBridge
    ) -> Bool? {
        ScriptSightCheck(game: game).sees(viewer: viewer, target: target, bridge: bridge)
    }

    func answerPathWaits() {
        let streamer = game.streamer
        if !state.pathWaits.isEmpty {
            state.pathWaitAnswers
                .merge(state.pathWaits.settle(streamer.npcMovementReadouts())) { first, _ in
                    first
                }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        state.pathWaitAnswers = state.pathWaitAnswers.filter { token, arrived in
            !scheduler.answer(token, returning: .boolean(arrived))
        }
    }
}

/// Loads the rest transforms of a model's nodes, and answers the lookups that waited for them.
struct ScriptModelNodeLoader {
    let game: any ScriptNodeBindingsHost
    let state: ScriptPartState

    /// Runs each waiting lookup whose model is in, then hands its answer to the
    /// scheduler, which takes it once the waiting call is queued.
    func answerNodeWaits() {
        guard let nodes = state.modelNodes, !state.nodeWaits.isEmpty else { return }
        for index in state.nodeWaits.indices where state.nodeWaits[index].answer == nil {
            let wait = state.nodeWaits[index]
            switch nodes.state(of: wait.path) {
            case let .ready(transforms):
                state.nodeWaits[index].answer = wait.then(
                    transforms[wait.node].map { wait.toWorld * $0.model }
                )
            case .failed:
                state.nodeWaits[index].answer = wait.then(nil)
            case .loading:
                continue
            }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        state.nodeWaits.removeAll { wait in
            guard let answer = wait.answer else { return false }
            return scheduler.answer(wait.token, returning: answer)
        }
    }

    nonisolated static func nodeTransforms(
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

/// Whether a viewer sees a target: the player through the camera's view, an NPC through
/// its detection.
struct ScriptSightCheck {
    let game: any ScriptNodeBindingsHost

    /// How far short of the target the trace stops, so the target's own collision
    /// does not hide it. About half a metre.
    private static let traceMargin: Float = 32

    func sees(
        viewer: ReferenceKey, target: ReferenceKey, bridge: PapyrusWorldStateBridge
    ) -> Bool? {
        guard viewer == .player else {
            return game.perception.perceptionResolution()
                .pair(observer: viewer, target: target)?.hasLineOfSight
        }
        guard
            let renderer = game.renderer, let gameSession = game.gameSession, let point = position(
                of: target,
                bridge: bridge
            )
        else { return nil }
        let projection = renderer.projectionMatrix
        guard projection.columns.0.x > 0, projection.columns.1.y > 0 else { return nil }
        let camera = gameSession.freeFlyCamera
        let view = LineOfSightWatch.View(
            forward: camera.forward, right: camera.right,
            up: simd_normalize(simd_cross(camera.right, camera.forward)),
            tanHalfWidth: 1 / projection.columns.0.x, tanHalfHeight: 1 / projection.columns.1.y
        )
        let offset = point - camera.position
        guard view.contains(offset) else { return false }
        let distance = simd_length(offset)
        guard distance > Self.traceMargin else { return true }
        let end = camera.position + offset * ((distance - Self.traceMargin) / distance)
        return game.aiWorld.perceptionHasLineOfSight(from: camera.position, to: end)
    }

    /// An actor's chest, or a placed object's origin.
    private func position(
        of key: ReferenceKey, bridge: PapyrusWorldStateBridge
    ) -> SIMD3<Float>? {
        if let feet = bridge.natives.perception.livePosition?(key) {
            return feet + SIMD3(0, 0, PlayerCapsule.standard.torsoHeight)
        }
        return bridge.placement(of: key)?.state.transform.position
    }
}
