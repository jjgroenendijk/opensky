// Plays a mesh's node controllers on one clock. Keys and paths set their node first,
// look-at turns read those results, and lag bones trail last, in world space.
// The rules: docs/formats/nif-controllers.md#what-opensky-does-with-them.

import Foundation
import simd

nonisolated public struct NIFNodeAnimator: Sendable {
    public let animation: NIFNodeAnimation
    /// Seconds since the animator started.
    public private(set) var time: Float = 0
    public private(set) var locals: [NIFNodeTransform]
    /// Nodes that hold their pose because the camera is beyond their bone LOD distance.
    public private(set) var frozen: Set<Int> = []
    /// Each lag bone's world transform, by controller index.
    private var lagged: [Int: NIFNodeTransform] = [:]

    public init(animation: NIFNodeAnimation) {
        self.animation = animation
        locals = animation.nodes.map(\.rest)
    }

    /// Advances the clock and poses every node. `placement` is the mesh in the world;
    /// lag bones trail its motion. `cameraDistance` nil plays every bone.
    public mutating func step(
        deltaTime: Float, placement: NIFNodeTransform = .identity, cameraDistance: Float? = nil
    ) {
        time += max(deltaTime, 0)
        frozen = cameraDistance.flatMap { distance in
            animation.boneLOD?.frozenNodes(atDistance: distance, in: animation)
        } ?? []
        let controllers = animation.controllers.enumerated().filter {
            $0.element.isActive && !frozen.contains($0.element.node)
        }
        for (_, controller) in controllers {
            let at = controller.timing.controllerTime(at: time)
            switch controller.motion {
            case let .keys(channel): locals[controller.node] = pose(
                    channel,
                    at: at,
                    controller.node
                )
            case let .path(path): locals[controller.node] = pose(path, at: at, controller.node)
            case .lookAt, .lag: continue
            }
        }
        for (_, controller) in controllers {
            guard case let .lookAt(lookAt) = controller.motion else { continue }
            locals[controller.node] = pose(
                lookAt, at: controller.timing.controllerTime(at: time), controller.node
            )
        }
        for (index, controller) in controllers {
            guard case let .lag(lag) = controller.motion else { continue }
            trail(controller.node, lag, controller: index, deltaTime: deltaTime, placement)
        }
    }

    /// The node's transform in the mesh.
    public func modelTransform(of node: Int) -> NIFNodeTransform {
        var transform = locals[node]
        var parent = animation.nodes[node].parent
        var depth = 0
        while let current = parent, depth < 64 {
            transform = locals[current].composed(with: transform)
            parent = animation.nodes[current].parent
            depth += 1
        }
        return transform
    }

    private func parentTransform(of node: Int) -> NIFNodeTransform {
        animation.nodes[node].parent.map(modelTransform) ?? .identity
    }

    private func pose(
        _ channel: NIFTransformChannel,
        at time: Float,
        _ node: Int
    ) -> NIFNodeTransform {
        let rest = animation.nodes[node].rest
        return NIFNodeTransform(
            translation: channel.translation(at: time) ?? rest.translation,
            rotation: channel.rotation(at: time) ?? rest.rotation,
            scale: channel.scale(at: time) ?? rest.scale
        )
    }

    private func pose(_ path: NIFPath, at time: Float, _ node: Int) -> NIFNodeTransform {
        var pose = animation.nodes[node].rest
        let fraction = path.fraction(at: time)
        pose.translation = path.position(atFraction: fraction) ?? pose.translation
        if let rotation = NIFPathOrientation.rotation(of: path, atFraction: fraction) {
            pose.rotation = rotation
        }
        return pose
    }

    private func pose(_ lookAt: NIFLookAt, at time: Float, _ node: Int) -> NIFNodeTransform {
        var pose = locals[node]
        pose.translation = NIFKeySampler.vector(lookAt.translation, at: time) ?? pose.translation
        pose.scale = NIFKeySampler.float(lookAt.scale, at: time) ?? pose.scale
        guard let target = lookAt.target else { return pose }
        let parent = parentTransform(of: node)
        let goal = parent.inverse.composed(with: modelTransform(of: target)).translation
        let roll = NIFKeySampler.float(lookAt.roll, at: time) ?? 0
        if let rotation = NIFPathOrientation.facing(
            goal - pose.translation,
            axis: lookAt.axis,
            roll: roll
        ) {
            pose.rotation = rotation
        }
        return pose
    }

    /// Moves the lag bone's world transform toward its rest under the parent, then
    /// expresses it in the parent's space again.
    private mutating func trail(
        _ node: Int, _ lag: NIFLagBone, controller: Int, deltaTime: Float,
        _ placement: NIFNodeTransform
    ) {
        let parent = placement.composed(with: parentTransform(of: node))
        let goal = parent.composed(with: animation.nodes[node].rest)
        let current = NIFLagBoneMotion.step(
            lagged[controller] ?? goal, toward: goal, lag, deltaTime: deltaTime
        )
        lagged[controller] = current
        locals[node] = parent.inverse.composed(with: current)
    }
}
