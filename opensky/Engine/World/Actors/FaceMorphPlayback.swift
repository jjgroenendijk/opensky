// Actor-local FaceGen expression composition and frame-safe GPU upload.
// TRI deltas are composed on the CPU because the named target set is sparse
// and controlled by the developer panel; the vertex shader consumes one
// position/normal delta pair per face vertex before skinning.

import Foundation
import Metal
import simd

nonisolated enum FaceMorphError: Error, Equatable {
    case vertexCountMismatch(tri: Int, mesh: Int)
    case bufferAllocationFailed
}

nonisolated struct FaceMorphTarget {
    let name: String
    let deltas: [MorphVertexDelta]
}

nonisolated enum FaceMorphComposer {
    static func targets(from tri: TRIFile) -> [FaceMorphTarget] {
        let baseNormals = normals(vertices: tri.baseVertices, triangles: tri.triangles)
        return tri.morphTargets.map { target in
            let positions = zip(tri.baseVertices, target.scaledDeltas).map(+)
            let morphedNormals = normals(vertices: positions, triangles: tri.triangles)
            return FaceMorphTarget(
                name: target.name,
                deltas: zip(target.scaledDeltas, zip(morphedNormals, baseNormals)).map {
                    MorphVertexDelta(position: $0.0, normal: $0.1.0 - $0.1.1)
                }
            )
        }
    }

    static func compose(
        targets: [FaceMorphTarget],
        weights: [String: Float],
        vertexCount: Int
    ) -> [MorphVertexDelta] {
        var positions = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        var normals = [SIMD3<Float>](repeating: .zero, count: vertexCount)
        for target in targets {
            let weight = min(max(weights[target.name] ?? 0, 0), 1)
            guard weight > 0, target.deltas.count == vertexCount else { continue }
            for index in 0 ..< vertexCount {
                positions[index] += target.deltas[index].position * weight
                normals[index] += target.deltas[index].normal * weight
            }
        }
        return zip(positions, normals).map(MorphVertexDelta.init)
    }

    private static func normals(
        vertices: [SIMD3<Float>],
        triangles: [TRITriangle]
    ) -> [SIMD3<Float>] {
        var sums = [SIMD3<Float>](repeating: .zero, count: vertices.count)
        for triangle in triangles {
            let a = Int(triangle.vertices.x)
            let b = Int(triangle.vertices.y)
            let third = Int(triangle.vertices.z)
            let normal = simd_cross(vertices[b] - vertices[a], vertices[third] - vertices[a])
            sums[a] += normal
            sums[b] += normal
            sums[third] += normal
        }
        return sums.map { simd_length_squared($0) > 0 ? simd_normalize($0) : .zero }
    }
}

nonisolated final class FaceMorphBuffer {
    let buffer: MTLBuffer
    let vertexCount: Int
    let targets: [FaceMorphTarget]
    private(set) var currentDeltas: [MorphVertexDelta]

    init(device: MTLDevice, tri: TRIFile, mesh: RenderMesh) throws {
        guard tri.baseVertices.count == mesh.vertexCount else {
            throw FaceMorphError.vertexCountMismatch(
                tri: tri.baseVertices.count, mesh: mesh.vertexCount
            )
        }
        vertexCount = mesh.vertexCount
        targets = FaceMorphComposer.targets(from: tri)
        currentDeltas = FaceMorphComposer.compose(
            targets: targets, weights: [:], vertexCount: vertexCount
        )
        let length = vertexCount * MorphVertexLayout.stride * Renderer.maxFramesInFlight
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw FaceMorphError.bufferAllocationFailed
        }
        self.buffer = buffer
        buffer.label = "\(mesh.name ?? "face").morph-deltas"
        for slot in 0 ..< Renderer.maxFramesInFlight {
            prepare(slot: slot)
        }
    }

    func update(weights: [String: Float]) {
        currentDeltas = FaceMorphComposer.compose(
            targets: targets, weights: weights, vertexCount: vertexCount
        )
    }

    func prepare(slot: Int) {
        buffer.contents().advanced(by: byteOffset(slot: slot)).copyMemory(
            from: currentDeltas,
            byteCount: vertexCount * MorphVertexLayout.stride
        )
    }

    func byteOffset(slot: Int) -> Int {
        slot * vertexCount * MorphVertexLayout.stride
    }
}

nonisolated struct FaceMorphAssociationMiss: Equatable {
    let headPart: FormID
    let reason: String
}

nonisolated protocol LipMorphWeightApplying: AnyObject {
    var actor: FormID { get }
    var targetNames: [String] { get }

    @discardableResult
    func setLipWeights(_ weights: [String: Float]) -> Int

    @discardableResult
    func clearLipWeights() -> Int
}

nonisolated final class FaceMorphPlayback: RenderAnimation, LipMorphWeightApplying {
    let actor: FormID
    let bindings: [ObjectIdentifier: FaceMorphBuffer]
    let pairedPaths: [String]
    let misses: [FaceMorphAssociationMiss]
    let worldBounds: ModelBounds?
    private var manualWeights: [String: Float] = [:]
    private var lipWeights: [String: Float] = [:]
    private(set) var unknownTargetCount = 0

    var weights: [String: Float] {
        var combined = manualWeights
        for (target, value) in lipWeights {
            combined[target] = min(max((combined[target] ?? 0) + value, 0), 1)
        }
        return combined
    }

    var targetNames: [String] {
        Array(Set(bindings.values.flatMap { $0.targets.map(\.name) })).sorted()
    }

    init(
        actor: FormID,
        bindings: [ObjectIdentifier: FaceMorphBuffer],
        pairedPaths: [String],
        misses: [FaceMorphAssociationMiss],
        worldBounds: ModelBounds?
    ) {
        self.actor = actor
        self.bindings = bindings
        self.pairedPaths = pairedPaths
        self.misses = misses
        self.worldBounds = worldBounds
    }

    @discardableResult
    func setWeight(_ weight: Float, for target: String) -> Bool {
        guard targetNames.contains(target) else {
            unknownTargetCount += 1
            return false
        }
        manualWeights[target] = min(max(weight.isFinite ? weight : 0, 0), 1)
        applyWeights()
        return true
    }

    @discardableResult
    func setLipWeights(_ weights: [String: Float]) -> Int {
        let targets = Set(targetNames)
        lipWeights = weights.filter { targets.contains($0.key) }
        return applyWeights()
    }

    @discardableResult
    func clearLipWeights() -> Int {
        guard !lipWeights.isEmpty else { return 0 }
        lipWeights.removeAll(keepingCapacity: true)
        return applyWeights()
    }

    @discardableResult
    func update(at _: Float) -> Int {
        0
    }

    @discardableResult
    func resetToBindPose() -> Int {
        manualWeights.removeAll(keepingCapacity: true)
        lipWeights.removeAll(keepingCapacity: true)
        return applyWeights()
    }

    @discardableResult
    private func applyWeights() -> Int {
        for buffer in bindings.values {
            buffer.update(weights: weights)
        }
        return bindings.count
    }
}
