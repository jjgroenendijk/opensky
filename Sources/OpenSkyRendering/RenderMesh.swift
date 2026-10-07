// Engine Mesh -> GPU buffers for the static-mesh pipeline. The interleaved layout is
// defined once here, so Swift packing and the shader's `stage_in` cannot drift. Missing
// attributes get neutral defaults, because vanilla NIFs omit them legitimately.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd
import Synchronization

nonisolated public enum RenderMeshError: Error, Equatable {
    /// Triangle index points past the vertex array (defensive: parsers
    /// validate, but this data ultimately comes from external files).
    case indexOutOfRange(index: UInt16, vertexCount: Int)
    case boneIndexOutOfRange(index: UInt16, boneCount: Int)
    case invalidSkinningData
    case emptyMesh
    case bufferAllocationFailed
}

/// Second stream for skinned meshes. Swift's SIMD alignment makes this 32
/// bytes (16-byte float4, 8-byte ushort4, tail padding); descriptor uses the
/// same MemoryLayout stride so CPU/GPU packing cannot drift.
nonisolated public struct SkinVertex: Sendable {
    public let weights: SIMD4<Float>
    public let boneIndices: SIMD4<UInt16>
}

nonisolated public enum SkinVertexLayout: Sendable {
    public static let weightsOffset = 0
    public static let boneIndicesOffset = 16
    public static let stride = MemoryLayout<SkinVertex>.stride

    public static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = StaticVertexLayout.vertexDescriptor()
        let buffer = BufferIndex.skinningAttributes.rawValue
        descriptor.attributes[VertexAttribute.boneWeights.rawValue].format = .float4
        descriptor.attributes[VertexAttribute.boneWeights.rawValue].offset = weightsOffset
        descriptor.attributes[VertexAttribute.boneWeights.rawValue].bufferIndex = buffer
        descriptor.attributes[VertexAttribute.boneIndices.rawValue].format = .ushort4
        descriptor.attributes[VertexAttribute.boneIndices.rawValue].offset = boneIndicesOffset
        descriptor.attributes[VertexAttribute.boneIndices.rawValue].bufferIndex = buffer
        descriptor.layouts[buffer].stride = stride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }
}

/// Actor-local FaceGen expression stream. SIMD3 occupies 16 bytes in Swift,
/// matching the explicitly separated float3 attributes Metal reads.
nonisolated public struct MorphVertexDelta: Sendable {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
}

nonisolated public enum MorphVertexLayout: Sendable {
    public static let positionOffset = 0
    public static let normalOffset = 16
    public static let stride = MemoryLayout<MorphVertexDelta>.stride

    public static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = SkinVertexLayout.vertexDescriptor()
        let buffer = BufferIndex.morphDeltas.rawValue
        descriptor.attributes[VertexAttribute.morphPositionDelta.rawValue].format = .float3
        descriptor.attributes[VertexAttribute.morphPositionDelta.rawValue].offset = positionOffset
        descriptor.attributes[VertexAttribute.morphPositionDelta.rawValue].bufferIndex = buffer
        descriptor.attributes[VertexAttribute.morphNormalDelta.rawValue].format = .float3
        descriptor.attributes[VertexAttribute.morphNormalDelta.rawValue].offset = normalOffset
        descriptor.attributes[VertexAttribute.morphNormalDelta.rawValue].bufferIndex = buffer
        descriptor.layouts[buffer].stride = stride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }
}

/// Interleaved layout of one static-mesh vertex: float3 position, float3
/// normal, float2 texcoord, float4 color — 48 bytes, tightly packed floats
/// (not simd-aligned; the vertex descriptor below is the single source of
/// truth for the shader's view of it).
nonisolated public enum StaticVertexLayout: Sendable {
    public static let positionOffset = 0
    public static let normalOffset = 12
    public static let texcoordOffset = 24
    public static let colorOffset = 32
    public static let stride = 48

    /// Attribute defaults for meshes that omit an array: +Z normal (world
    /// up, docs/decisions/coordinates.md), origin UV, opaque white color.
    public static let defaultNormal = SIMD3<Float>(0, 0, 1)
    public static let defaultColor = SIMD4<Float>(1, 1, 1, 1)

    public static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        let buffer = BufferIndex.vertices.rawValue

        func set(_ attribute: VertexAttribute, _ format: MTLVertexFormat, _ offset: Int) {
            descriptor.attributes[attribute.rawValue].format = format
            descriptor.attributes[attribute.rawValue].offset = offset
            descriptor.attributes[attribute.rawValue].bufferIndex = buffer
        }
        set(.position, .float3, positionOffset)
        set(.normal, .float3, normalOffset)
        set(.texcoord, .float2, texcoordOffset)
        set(.color, .float4, colorOffset)

        descriptor.layouts[buffer].stride = stride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }

    /// Packs a mesh's attribute arrays into the interleaved layout above.
    /// Mesh contract: attribute arrays are empty or vertex-count sized.
    public static func interleave(_ mesh: Mesh) -> [Float] {
        var floats: [Float] = []
        floats.reserveCapacity(mesh.positions.count * stride / MemoryLayout<Float>.size)
        for index in mesh.positions.indices {
            let position = mesh.positions[index]
            let normal = index < mesh.normals.count ? mesh.normals[index] : defaultNormal
            let uv = index < mesh.uvs.count ? mesh.uvs[index] : .zero
            let color = index < mesh.colors.count ? mesh.colors[index] : defaultColor
            floats.append(contentsOf: [
                position.x, position.y, position.z,
                normal.x, normal.y, normal.z,
                uv.x, uv.y,
                color.x, color.y, color.z, color.w
            ])
        }
        return floats
    }
}

/// Terrain vertex layout: the static interleaved stream plus a second buffer
/// (BufferIndexTerrainWeights) carrying two float4 splat-weight lanes per
/// vertex — up to TerrainConstantMaxLayers (8) ATXT layer opacities. Kept as
/// a parallel stream instead of forking the 48-byte static layout so
/// RenderMesh upload and StaticVertexLayout stay untouched
/// (docs/rendering/scene-drawing.md, terrain splat section).
nonisolated public enum TerrainVertexLayout: Sendable {
    /// Two tightly packed float4 lanes per vertex.
    public static let weightsStride = 32

    public static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = StaticVertexLayout.vertexDescriptor()
        let buffer = BufferIndex.terrainWeights.rawValue

        func set(_ attribute: VertexAttribute, _ offset: Int) {
            descriptor.attributes[attribute.rawValue].format = .float4
            descriptor.attributes[attribute.rawValue].offset = offset
            descriptor.attributes[attribute.rawValue].bufferIndex = buffer
        }
        set(.layerWeights0, 0)
        set(.layerWeights1, 16)

        descriptor.layouts[buffer].stride = weightsStride
        descriptor.layouts[buffer].stepRate = 1
        descriptor.layouts[buffer].stepFunction = .perVertex
        return descriptor
    }
}

/// One mesh's GPU residence: interleaved vertex buffer + uint16 index
/// buffer, plus the mesh-local -> model-root transform and material slot
/// carried over from the engine Mesh.
nonisolated public final class RenderMesh: Sendable {
    public let name: String?
    public let vertexCount: Int
    public let vertexBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public let skinningBuffer: MTLBuffer?
    public let boneMatrixBuffer: MTLBuffer?
    private let skinningPalette: SkinningPalette?
    /// Written on the main actor after the build queue hands the mesh over.
    private let boneMatrices: Mutex<[float4x4]>
    /// The skeleton this mesh last bound to and where each palette bone reads from it.
    private let skeletonBinding = Mutex<(bones: SkeletonBoneIndex, indices: [Int])?>(nil)
    public var currentBoneMatrices: [float4x4] {
        boneMatrices.withLock { $0 }
    }

    public var isSkinned: Bool {
        skinningBuffer != nil
    }

    /// Mesh-local -> model-root transform (see Geometry/Mesh.swift).
    public let localTransform: float4x4
    /// Mesh-local bounds retained for vertex effects that need normalized
    /// height (grass sway). RenderModel also retains model-root bounds for
    /// placement culling through MeshLibrary.
    public let localBounds: ModelBounds
    /// Index into the owning model's materials.
    public let materialSlot: Int
    /// UV units per mesh-local unit, for texture streaming.
    public let uvPerUnit: Float

    public init(device: MTLDevice, mesh: Mesh) throws {
        guard !mesh.positions.isEmpty, !mesh.indices.isEmpty else {
            throw RenderMeshError.emptyMesh
        }
        guard let localBounds = ModelBounds.containing(mesh.positions) else {
            throw RenderMeshError.emptyMesh
        }
        if let bad = mesh.indices.first(where: { Int($0) >= mesh.positions.count }) {
            throw RenderMeshError.indexOutOfRange(
                index: bad,
                vertexCount: mesh.positions.count
            )
        }

        let vertices = StaticVertexLayout.interleave(mesh)
        let skinBuffers = try Self.makeSkinBuffers(device: device, mesh: mesh)
        guard
            let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<Float>.size,
                options: .storageModeShared
            ),
            let indexBuffer = device.makeBuffer(
                bytes: mesh.indices,
                length: mesh.indices.count * MemoryLayout<UInt16>.size,
                options: .storageModeShared
            ) else { throw RenderMeshError.bufferAllocationFailed }
        vertexBuffer.label = "\(mesh.name ?? "mesh").vertices"
        indexBuffer.label = "\(mesh.name ?? "mesh").indices"

        name = mesh.name
        vertexCount = mesh.positions.count
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = mesh.indices.count
        skinningBuffer = skinBuffers.attributes
        boneMatrixBuffer = skinBuffers.matrices
        skinningPalette = skinBuffers.palette
        boneMatrices = Mutex(mesh.skinning?.bindPoseMatrices ?? [])
        localTransform = mesh.transform
        self.localBounds = localBounds
        materialSlot = mesh.materialSlot
        uvPerUnit = MeshUVDensity.uvPerUnit(
            positions: mesh.positions, uvs: mesh.uvs, indices: mesh.indices
        )
    }

    private struct SkinBuffers {
        let attributes: MTLBuffer?
        let matrices: MTLBuffer?
        let palette: SkinningPalette?
    }

    private static func makeSkinBuffers(
        device: MTLDevice,
        mesh: Mesh
    ) throws -> SkinBuffers {
        guard let skinning = mesh.skinning else {
            return SkinBuffers(attributes: nil, matrices: nil, palette: nil)
        }
        guard
            skinning.weights.count == mesh.positions.count,
            skinning.boneIndices.count == mesh.positions.count,
            !skinning.bindPoseMatrices.isEmpty
        else { throw RenderMeshError.invalidSkinningData }
        let boneCount = skinning.bindPoseMatrices.count
        let allIndices = skinning.boneIndices.flatMap { [$0.x, $0.y, $0.z, $0.w] }
        if let index = allIndices.first(where: { Int($0) >= boneCount }) {
            throw RenderMeshError.boneIndexOutOfRange(
                index: index,
                boneCount: boneCount
            )
        }
        let vertices = zip(skinning.weights, skinning.boneIndices).map(SkinVertex.init)
        guard
            let attributes = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<SkinVertex>.stride,
                options: .storageModeShared
            ),
            let matrices = device.makeBuffer(
                length: skinning.bindPoseMatrices.count * MemoryLayout<float4x4>.stride
                    * Renderer.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RenderMeshError.bufferAllocationFailed }
        attributes.label = "\(mesh.name ?? "mesh").skin-vertices"
        matrices.label = "\(mesh.name ?? "mesh").bone-palettes"
        for slot in 0 ..< Renderer.maxFramesInFlight {
            matrices.contents().advanced(
                by: slot * skinning.bindPoseMatrices.count * MemoryLayout<float4x4>.stride
            ).copyMemory(
                from: skinning.bindPoseMatrices,
                byteCount: skinning.bindPoseMatrices.count * MemoryLayout<float4x4>.stride
            )
        }
        return SkinBuffers(
            attributes: attributes,
            matrices: matrices,
            palette: SkinningPalette(skinning)
        )
    }

    /// Refreshes CPU palette from an animated skeleton world pose. Unmatched
    /// helper/NIF-only bones keep their verified bind matrix.
    @discardableResult
    public func updateSkinningPose(_ transformsByName: [String: float4x4]) -> Int {
        guard let palette = skinningPalette else { return 0 }
        let posed = palette.posed(by: transformsByName)
        boneMatrices.withLock { $0 = posed.matrices }
        return posed.matchedBoneCount
    }

    /// The same refresh from a pose in skeleton bone order. The palette maps its bones
    /// to that skeleton once, so a frame hashes no bone names.
    @discardableResult
    public func updateSkinningPose(_ pose: SkeletonPose) -> Int {
        guard let palette = skinningPalette else { return 0 }
        let indices = skeletonBinding.withLock { binding in
            if let binding, binding.bones === pose.bones {
                return binding.indices
            }
            let indices = palette.skeletonIndices(in: pose.bones)
            binding = (pose.bones, indices)
            return indices
        }
        return boneMatrices.withLock { palette.pose(pose, through: indices, into: &$0) }
    }

    /// Restores verified NIF bind matrices for actor-animation A/B. Returns
    /// palette size so live inspection can prove resident skinning work ran.
    @discardableResult
    public func resetSkinningPose() -> Int {
        guard let palette = skinningPalette else { return 0 }
        boneMatrices.withLock { $0 = palette.bindPoseMatrices }
        return palette.bindPoseMatrices.count
    }

    /// Copies current CPU palette into this frame-in-flight slot immediately
    /// before encoding, so CPU updates never race prior GPU frames.
    public func prepareBoneMatrices(slot: Int) {
        guard let buffer = boneMatrixBuffer else { return }
        boneMatrices.withLock { matrices in
            guard !matrices.isEmpty else { return }
            let offset = slot * matrices.count * MemoryLayout<float4x4>.stride
            buffer.contents().advanced(by: offset).copyMemory(
                from: matrices,
                byteCount: matrices.count * MemoryLayout<float4x4>.stride
            )
        }
    }

    public func boneMatrixOffset(slot: Int) -> Int {
        slot * boneMatrices.withLock { $0.count } * MemoryLayout<float4x4>.stride
    }
}
