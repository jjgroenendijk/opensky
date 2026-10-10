// The cloud dome and the weather's cloud textures. Both load off the main actor; the
// frame drains them and builds the GPU copies (docs/engine/weather.md "Clouds").

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyShaderTypes
import simd

/// The dome's shapes in child order, so shape `n` carries cloud layer `n`.
nonisolated public struct CloudDomeGeometry: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var colors: [SIMD4<Float>] = []
    public var texcoords: [SIMD2<Float>] = []
    public var indices: [UInt32] = []
    /// Ranges into `indices`, one per shape.
    public var shapes: [Range<Int>] = []

    public init() {}

    /// Positions and normals are already in model space after the shape transform.
    public init(model: Model) {
        for mesh in model.meshes {
            let base = UInt32(positions.count)
            for (index, position) in mesh.positions.enumerated() {
                let placed = mesh.transform * SIMD4(position, 1)
                positions.append(SIMD3(placed.x, placed.y, placed.z))
                colors.append(index < mesh.colors.count ? mesh.colors[index] : SIMD4(1, 1, 1, 1))
                texcoords.append(index < mesh.uvs.count ? mesh.uvs[index] : .zero)
            }
            let start = indices.count
            indices.append(contentsOf: mesh.indices.map { base + UInt32($0) })
            shapes.append(start ..< indices.count)
        }
    }
}

nonisolated enum SkyCloudAsset: Sendable {
    case dome(CloudDomeGeometry)
    case texture(Data)
}

public final class SkyClouds {
    nonisolated public static let domePath = "meshes\\sky\\clouds.nif"
    /// Two weathers of 32 layers each, during a transition.
    public static let maximumDraws = 64
    static let uniformStride = 256

    struct Dome {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let shapes: [Range<Int>]
    }

    private let loader: AssetLoader<String, SkyCloudAsset>
    private let device: MTLDevice
    private let textureLoader: TextureLoader
    private(set) var dome: Dome?
    private var textures: [String: MTLTexture] = [:]
    private var domeRequested = false
    private var uniformsResident = false
    let uniforms: MTLBuffer
    /// Layers drawn in the last frame, for the sidebar readout.
    public internal(set) var drawnLayerCount = 0
    public private(set) var failedPaths: [String] = []

    /// `immediate` loads inside the request, for offscreen frames and tests.
    public init(fileSystem: any GameFileSource, device: MTLDevice, immediate: Bool = false) throws {
        let load: @Sendable (String) throws -> SkyCloudAsset = { path in
            let data = try fileSystem.contents(forPath: path)
            guard path == Self.domePath else { return .texture(data) }
            return try .dome(CloudDomeGeometry(model: NIFFile(data: data).model()))
        }
        loader = immediate
            ? AssetLoader(worker: ImmediateAssetLoadWorker(load: load))
            : AssetLoader(load: load)
        self.device = device
        textureLoader = try TextureLoader(device: device)
        let length = Renderer.maxFramesInFlight * Self.maximumDraws * Self.uniformStride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }
        buffer.label = "CloudLayerUniforms"
        uniforms = buffer
    }

    /// The record spells a layer texture relative to `textures\`.
    public static func texturePath(_ texture: String) -> String {
        let path = "textures\\" + texture
        return (try? VirtualFileSystem.normalize(path)) ?? path.lowercased()
    }

    func texture(_ texture: String) -> MTLTexture? {
        textures[Self.texturePath(texture)]
    }

    /// Moves finished loads in and asks for what `layers` needs. Returns new GPU
    /// allocations, which the caller makes resident.
    func prepare(_ layers: [ResolvedCloudLayer]) -> [MTLAllocation] {
        var added: [MTLAllocation] = uniformsResident ? [] : [uniforms]
        uniformsResident = true
        if !domeRequested {
            domeRequested = true
            loader.prefetch(Self.domePath)
        }
        for layer in layers where textures[Self.texturePath(layer.texture)] == nil {
            loader.prefetch(Self.texturePath(layer.texture))
        }
        for path in loader.drain() {
            switch loader.state(of: path) {
            case let .ready(.dome(geometry)):
                if let built = makeDome(geometry) {
                    dome = built
                    added += [built.vertices, built.indices]
                }
            case let .ready(.texture(data)):
                let texture = textureLoader.texture(dds: data, usage: .color, label: path)
                textures[path] = texture
                added.append(texture)
            case let .failed(failure):
                failedPaths.append("\(path): \(failure)")
            case .loading, .ready:
                break
            }
        }
        // The GPU copies are kept, so the loaded bytes can go.
        loader.evict { _ in true }
        return added
    }

    private func makeDome(_ geometry: CloudDomeGeometry) -> Dome? {
        let vertices = geometry.positions.indices.map { index in
            CloudVertex(
                position: SIMD4(geometry.positions[index], 1),
                color: geometry.colors[index],
                texcoord: geometry.texcoords[index],
                padding: .zero
            )
        }
        guard
            !vertices.isEmpty, !geometry.indices.isEmpty,
            let vertexBuffer = device.makeBuffer(
                bytes: vertices, length: vertices.count * MemoryLayout<CloudVertex>.stride,
                options: .storageModeShared
            ),
            let indexBuffer = device.makeBuffer(
                bytes: geometry.indices,
                length: geometry.indices.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
        else {
            failedPaths.append("\(Self.domePath): empty or not allocated")
            return nil
        }
        vertexBuffer.label = "CloudDomeVertices"
        indexBuffer.label = "CloudDomeIndices"
        return Dome(vertices: vertexBuffer, indices: indexBuffer, shapes: geometry.shapes)
    }
}
