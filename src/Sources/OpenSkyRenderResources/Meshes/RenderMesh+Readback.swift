// A mesh's rest vertices and triangles read back from its shared buffers, for a CPU
// simulation of the drawn shape, such as the cape cloth (docs/engine/cape-cloth.md).

import Foundation
@preconcurrency @unsafe import Metal
import OpenSkyFormatsCore
import simd

nonisolated extension RenderMesh {
    /// Each vertex position in the mesh's own space, as uploaded.
    public func restPositions() -> [SIMD3<Float>] {
        let base = unsafe vertexBuffer.contents()
        return (0 ..< vertexCount).map { vertex in
            let start = vertex * InterleavedVertexLayout.stride
                + InterleavedVertexLayout.positionOffset
            let floats = unsafe base.advanced(by: start).assumingMemoryBound(to: Float.self)
            return unsafe SIMD3(floats[0], floats[1], floats[2])
        }
    }

    /// The triangle list, three indices per triangle.
    public func triangleIndices() -> [UInt16] {
        let indices = unsafe indexBuffer.contents().assumingMemoryBound(to: UInt16.self)
        return (0 ..< indexCount).map { unsafe indices[$0] }
    }
}
