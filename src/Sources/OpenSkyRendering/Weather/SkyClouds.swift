// The cloud dome and the weather's cloud textures. Both load off the main actor; the
// frame drains them and builds the GPU copies (docs/engine/weather.md "Clouds").

public import Foundation
public import Metal
public import OpenSkyFormatsCore
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// The dome's shapes in child order, so shape `n` carries cloud layer `n`.
nonisolated public struct CloudDomeGeometry: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var colors: [SIMD4<Float>] = []
    public var texcoords: [SIMD2<Float>] = []
    public var normals: [SIMD3<Float>] = []
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
                let normal = index < mesh.normals.count ? mesh.normals[index] : SIMD3(0, 0, 1)
                let turned = mesh.transform * SIMD4(normal, 0)
                normals.append(simd_normalize(SIMD3(turned.x, turned.y, turned.z)))
            }
            let start = indices.count
            indices.append(contentsOf: mesh.indices.map { base + UInt32($0) })
            shapes.append(start ..< indices.count)
        }
    }

    /// The GPU vertex and index buffers; nil when empty or not allocated.
    func makeBuffers(device: any MTLDevice) -> (vertices: any MTLBuffer, indices: any MTLBuffer)? {
        let vertices = positions.indices.map { index in
            CloudVertex(
                position: SIMD4(positions[index], 1),
                color: colors[index],
                texcoord: texcoords[index],
                padding: .zero,
                normal: SIMD4(normals[index], 0)
            )
        }
        guard
            !vertices.isEmpty, !indices.isEmpty,
            let vertexBuffer = unsafe device.makeBuffer(
                bytes: vertices, length: vertices.count * MemoryLayout<CloudVertex>.stride,
                options: .storageModeShared
            ),
            let indexBuffer = unsafe device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
        else { return nil }
        return (vertexBuffer, indexBuffer)
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
        let vertices: any MTLBuffer
        let indices: any MTLBuffer
        let shapes: [Range<Int>]
    }

    private let loader: AssetLoader<String, SkyCloudAsset>
    private let device: any MTLDevice
    private let textureLoader: TextureLoader
    private(set) var dome: Dome?
    private var textures: [String: any MTLTexture] = [:]
    private var domeRequested = false
    private var uniformsResident = false
    let uniforms: any MTLBuffer
    /// Layers drawn in the last frame.
    public internal(set) var drawnLayerCount = 0
    public private(set) var failedPaths: [String] = []

    /// `immediate` loads inside the request, for offscreen frames and tests.
    public init(
        fileSystem: any GameFileSource,
        device: any MTLDevice,
        immediate: Bool = false
    ) throws {
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
        let length = GPUFactory.maxFramesInFlight * Self.maximumDraws * Self.uniformStride
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }
        buffer.label = "CloudLayerUniforms"
        uniforms = buffer
    }

    /// The record spells a layer texture relative to `textures\`.
    public static func texturePath(_ texture: String) -> String {
        let path = "textures\\" + texture
        return attempt { try VirtualFileSystem.normalize(path) } ?? path.lowercased()
    }

    func texture(_ texture: String) -> any MTLTexture? {
        textures[Self.texturePath(texture)]
    }

    /// Moves finished loads in and asks for what `layers` needs. Returns new GPU
    /// allocations, which the caller makes resident.
    func prepare(_ layers: [ResolvedCloudLayer]) -> [any MTLAllocation] {
        var added: [any MTLAllocation] = uniformsResident ? [] : [uniforms]
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
        guard let (vertexBuffer, indexBuffer) = geometry.makeBuffers(device: device) else {
            failedPaths.append("\(Self.domePath): empty or not allocated")
            return nil
        }
        vertexBuffer.label = "CloudDomeVertices"
        indexBuffer.label = "CloudDomeIndices"
        return Dome(vertices: vertexBuffer, indices: indexBuffer, shapes: geometry.shapes)
    }
}
