// Plays the node controllers of each resident placed mesh on its own clock and
// publishes the moved nodes. The rules live in `NIFNodeAnimator`
// (docs/engine/object-animation.md#node-controllers).

import OpenSkyActorPresentation
import OpenSkyFormatsMesh
import simd

/// What the node controller coordinator reads from the session.
@MainActor
public protocol NodeControllerWorld: AnyObject {
    func residentNodeAnimations() -> [CellNodeAnimation]
    /// Where bone LOD distances are measured from. Nil plays every bone.
    var nodeControllerViewer: SIMD3<Float>? { get }
}

/// One node of a running mesh, for `game state nodes`.
nonisolated public struct NodeControllerNodeRow: Equatable, Sendable {
    public let name: String
    /// Translation in the mesh's own space.
    public let translation: SIMD3<Float>
    public let rotation: simd_quatf
    public let controllers: [String]
    public let isActive: Bool
    public let isFrozen: Bool
}

@MainActor
public final class NodeControllerCoordinator {
    final class Running {
        var mesh: CellNodeAnimation
        var animator: NIFNodeAnimator

        init(mesh: CellNodeAnimation) {
            self.mesh = mesh
            animator = NIFNodeAnimator(animation: mesh.rig.animation)
        }
    }

    weak let world: (any NodeControllerWorld)?
    private(set) var running: [UInt32: Running] = [:]
    /// Off holds every mesh in the pose it has.
    public var isEnabled = true

    public init(world: any NodeControllerWorld) {
        self.world = world
    }

    /// Adopts new meshes and drops departed ones. A rebuilt cell brings a new pose
    /// buffer, and the clock keeps running into it.
    public func sync() {
        guard let world else { return }
        var seen = Set<UInt32>()
        for mesh in world.residentNodeAnimations() where seen.insert(mesh.reference).inserted {
            if let current = running[mesh.reference] {
                current.mesh = mesh
                continue
            }
            running[mesh.reference] = Running(mesh: mesh)
        }
        for reference in running.keys where !seen.contains(reference) {
            running.removeValue(forKey: reference)
        }
    }

    /// Steps every mesh in reference order and publishes its moved nodes.
    public func tick(deltaTime: Float) {
        guard isEnabled, deltaTime > 0 else { return }
        let viewer = world?.nodeControllerViewer
        for reference in running.keys.sorted() {
            guard let entry = running[reference] else { continue }
            let placement = Self.transform(entry.mesh.placement)
            entry.animator.step(
                deltaTime: deltaTime, placement: placement,
                cameraDistance: viewer.map { simd_distance($0, placement.translation) }
            )
            entry.mesh.pose.publish(entry.mesh.rig.bonePoses(entry.animator))
        }
    }

    /// The references that play node controllers, in order.
    public var references: [UInt32] {
        running.keys.sorted()
    }

    /// Each node a controller of the mesh drives, or nil when the reference plays none.
    public func nodes(of reference: UInt32) -> [NodeControllerNodeRow]? {
        guard let entry = running[reference] else { return nil }
        let animation = entry.mesh.rig.animation
        let driven = Dictionary(grouping: animation.controllers, by: \.node)
        return driven.keys.sorted().map { node in
            let transform = entry.animator.modelTransform(of: node)
            let controllers = driven[node] ?? []
            return NodeControllerNodeRow(
                name: animation.nodes[node].name ?? "",
                translation: transform.translation, rotation: transform.rotation,
                controllers: controllers.map(\.typeName),
                isActive: controllers.contains(where: \.isActive),
                isFrozen: entry.animator.frozen.contains(node)
            )
        }
    }

    /// The placement as a node transform; a placed reference has uniform scale.
    static func transform(_ matrix: float4x4) -> NIFNodeTransform {
        let x = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let y = SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let z = SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let scale = simd_length(x)
        guard scale > 0 else { return .identity }
        return NIFNodeTransform(
            translation: SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z),
            rotation: simd_quatf(simd_float3x3(x / scale, y / scale, z / scale)).normalized,
            scale: scale
        )
    }
}
