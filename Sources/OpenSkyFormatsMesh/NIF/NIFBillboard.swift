// How an `NiBillboardNode` turns to the camera, by its nif.xml `BillboardMode`.
// The modes and the axis each one turns: docs/formats/nif-sequences.md#billboard-nodes.

import Foundation
import simd

nonisolated public enum NIFBillboard {
    public static let typeName = "NiBillboardNode"

    /// The camera a billboard turns to.
    public struct Viewer: Equatable, Sendable {
        public let eye: SIMD3<Float>
        /// The view direction. Nil turns the camera-facing modes to the eye instead.
        public let forward: SIMD3<Float>?
        public let up: SIMD3<Float>

        public init(eye: SIMD3<Float>, forward: SIMD3<Float>?, up: SIMD3<Float>) {
            self.eye = eye
            self.forward = forward
            self.up = up
        }

        /// The same camera in the space that `placement` maps to the world.
        public func local(to placement: float4x4) -> Self {
            let inverse = placement.inverse
            func direction(_ vector: SIMD3<Float>) -> SIMD3<Float> {
                let moved = inverse * SIMD4(vector, 0)
                return simd_normalize(SIMD3(moved.x, moved.y, moved.z))
            }
            let point = inverse * SIMD4(eye, 1)
            return Self(
                eye: SIMD3(point.x, point.y, point.z), forward: forward.map(direction),
                up: direction(up)
            )
        }
    }

    /// The mode is the last 2 bytes of the block, after the `NiNode` fields.
    public static func mode(of block: NIFFile.Block) -> UInt16? {
        guard block.typeName == typeName, block.data.count >= 2 else { return nil }
        let end = block.data.endIndex
        return UInt16(block.data[end - 2]) | UInt16(block.data[end - 1]) << 8
    }

    /// The node's rotation once it faces `viewer`. `rotation` is its authored rotation and
    /// `origin` its position, both in the viewer's space. Nil where the view is degenerate.
    public static func rotation(
        mode: UInt16, rotation: simd_quatf, origin: SIMD3<Float>, viewer: Viewer
    ) -> simd_quatf? {
        let toEye = viewer.eye - origin
        // nif.xml stores the mode in the lowest 3 bits; 9 is 1 again.
        switch mode & 0x7 {
        case 1, 9:
            // Turns about its own +Y; +Z goes toward the eye.
            let axis = rotation.act([0, 1, 0])
            guard let front = flattened(toEye, across: axis) else { return nil }
            return basis(x: simd_cross(axis, front), y: axis, z: front)
        case 5:
            // Turns about its own +Z; -Y goes toward the eye.
            let axis = rotation.act([0, 0, 1])
            guard let front = flattened(toEye, across: axis) else { return nil }
            return basis(x: simd_cross(-front, axis), y: -front, z: axis)
        case 0:
            return minimised(rotation, to: viewer.forward.map { -$0 } ?? toEye)
        case 2:
            return facing(viewer.forward.map { -$0 } ?? toEye, up: viewer.up)
        case 3:
            return minimised(rotation, to: toEye)
        default:
            return facing(toEye, up: viewer.up)
        }
    }

    /// nif.xml "minimized rotation": the shortest turn that takes own +Z to `front`, so
    /// the node keeps as much of its authored roll as it can.
    private static func minimised(_ rotation: simd_quatf, to front: SIMD3<Float>) -> simd_quatf? {
        guard simd_length(front) > 1e-6 else { return nil }
        let from = rotation.act([0, 0, 1])
        let to = simd_normalize(front)
        let turn = if simd_dot(from, to) < -0.9999 {
            // Opposite: half a turn about own +Y.
            simd_quatf(angle: .pi, axis: rotation.act([0, 1, 0]))
        } else {
            simd_quatf(from: from, to: to)
        }
        let result = (turn * rotation).normalized
        return result.vector.x.isFinite ? result : nil
    }

    /// +Z along `front`, +Y as near `up` as the turn allows.
    private static func facing(_ front: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf? {
        guard simd_length(front) > 1e-6 else { return nil }
        let front = simd_normalize(front)
        guard let top = flattened(up, across: front) else { return nil }
        return basis(x: simd_cross(top, front), y: top, z: front)
    }

    /// `vector` with its part along the unit `axis` removed, made unit length.
    private static func flattened(
        _ vector: SIMD3<Float>,
        across axis: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let flat = vector - simd_dot(vector, axis) * axis
        let length = simd_length(flat)
        return length > 1e-6 ? flat / length : nil
    }

    private static func basis(x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>) -> simd_quatf? {
        guard x.x.isFinite, y.x.isFinite, z.x.isFinite else { return nil }
        return simd_quatf(simd_float3x3(x, y, z)).normalized
    }
}
