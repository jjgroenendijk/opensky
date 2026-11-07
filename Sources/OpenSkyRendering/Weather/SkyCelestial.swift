// The star and aurora meshes and the sun, glare, and moon textures. They load off the
// main actor; the frame drains them and builds the GPU copies
// (docs/engine/celestial-sky.md "Drawing").

public import Foundation
public import Metal
public import OpenSkyFormatsCore
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRenderResources
import simd

/// A sky mesh's shapes, each with its texture and how it blends.
nonisolated public struct SkyMeshGeometry: Sendable {
    public struct Shape: Sendable {
        public let indices: Range<Int>
        /// A normalized VFS key; nil draws nothing.
        public let texture: String?
        public let palette: String?
        public let effect: EffectShading
        /// UV offset in xy, scale in zw.
        public let uvTransform: SIMD4<Float>
        /// The source material, kept only when its shader values animate.
        public let animated: Material?

        /// The effect shading and UV transform at `seconds` of animation time.
        func shading(at seconds: Float) -> (effect: EffectShading, uvTransform: SIMD4<Float>) {
            guard let animated, let animation = animated.animation else {
                return (effect, uvTransform)
            }
            let moved = animation.apply(to: animated, at: seconds)
            return (moved.effect ?? effect, SIMD4(lowHalf: moved.uvOffset, highHalf: moved.uvScale))
        }
    }

    /// A shape without effect shading still fades by its vertex alpha.
    static let plainShading = EffectShading(
        baseColor: SIMD4(repeating: 1), baseColorScale: 1, paletteTexture: nil,
        paletteColor: false, paletteAlpha: false, falloff: nil, vertexColors: false,
        vertexAlpha: true
    )

    public let geometry: CloudDomeGeometry
    public let shapes: [Shape]

    public init(model: Model) {
        geometry = CloudDomeGeometry(model: model)
        shapes = zip(model.meshes, geometry.shapes).map { mesh, range in
            let material = model.materials.indices.contains(mesh.materialSlot)
                ? model.materials[mesh.materialSlot] : nil
            let effect = material?.effect ?? Self.plainShading
            let usesPalette = effect.paletteColor || effect.paletteAlpha
            return Shape(
                indices: range,
                texture: material?.diffuseTexture.flatMap(SkyCelestial.key),
                palette: usesPalette ? effect.paletteTexture.flatMap(SkyCelestial.key) : nil,
                effect: effect,
                uvTransform: material
                    .map { SIMD4(lowHalf: $0.uvOffset, highHalf: $0.uvScale) } ?? SIMD4(
                        0,
                        0,
                        1,
                        1
                    ),
                animated: material?.animation == nil ? nil : material
            )
        }
    }
}

nonisolated enum SkyObjectAsset: Sendable {
    case mesh(SkyMeshGeometry)
    case texture(Data)
}

public final class SkyCelestial {
    /// The stars, two auroras during a transition, the sun, its glare, and two moons.
    public static let maximumDraws = 32
    static let uniformStride = 256

    struct Mesh {
        let vertices: any MTLBuffer
        let indices: any MTLBuffer
        let shapes: [SkyMeshGeometry.Shape]
    }

    private let loader: AssetLoader<String, SkyObjectAsset>
    private let device: any MTLDevice
    private let textureLoader: TextureLoader
    private var meshes: [String: Mesh] = [:]
    private var textures: [String: any MTLTexture] = [:]
    private var requested: Set<String> = []
    private var uniformsResident = false
    let uniforms: any MTLBuffer
    /// Objects drawn in the last frame.
    public internal(set) var drawnObjectCount = 0
    public private(set) var failedPaths: [String] = []

    /// `immediate` loads inside the request, for offscreen frames and tests.
    public init(
        fileSystem: any GameFileSource,
        device: any MTLDevice,
        immediate: Bool = false
    ) throws {
        let load: @Sendable (String) throws -> SkyObjectAsset = { path in
            let data = try fileSystem.contents(forPath: path)
            guard path.hasSuffix(".nif") else { return .texture(data) }
            return try .mesh(SkyMeshGeometry(model: NIFFile(data: data).model()))
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
        buffer.label = "SkyObjectUniforms"
        uniforms = buffer
    }

    nonisolated static func key(_ path: String) -> String? {
        try? VirtualFileSystem.normalize(path)
    }

    /// A record names its textures relative to `textures\` and its models to `meshes\`.
    nonisolated public static func textureKey(_ relative: String) -> String? {
        key("textures\\" + relative)
    }

    nonisolated public static func meshKey(_ relative: String) -> String? {
        key("meshes\\" + relative)
    }

    func texture(key: String?) -> any MTLTexture? {
        key.flatMap { textures[$0] }
    }

    func mesh(key: String?) -> Mesh? {
        key.flatMap { meshes[$0] }
    }

    /// Moves finished loads in and asks for what `sky` needs. Returns new GPU
    /// allocations, which the caller makes resident.
    func prepare(_ sky: CelestialSky) -> [any MTLAllocation] {
        var added: [any MTLAllocation] = uniformsResident ? [] : [uniforms]
        uniformsResident = true
        var textureNames = [sky.sunTexture, sky.glareTexture] + sky.moons.map(\.texture)
        if !sky.moons.isEmpty {
            textureNames.append(CelestialSky.moonShadowTexture)
        }
        var wanted = textureNames.compactMap { $0.flatMap(Self.textureKey) }
        wanted += ([sky.nightSkyModel] + sky.auroras.map(\.model)).compactMap {
            $0.flatMap(Self.meshKey)
        }
        for mesh in meshes.values {
            wanted += mesh.shapes.flatMap { [$0.texture, $0.palette] }.compactMap(\.self)
        }
        for path in wanted where !requested.contains(path) {
            requested.insert(path)
            loader.prefetch(path)
        }
        for path in loader.drain() {
            added += adopt(path)
        }
        // The GPU copies are kept, so the loaded bytes can go.
        loader.evict { _ in true }
        return added
    }

    private func adopt(_ path: String) -> [any MTLAllocation] {
        switch loader.state(of: path) {
        case let .ready(.mesh(geometry)):
            guard let built = makeMesh(geometry, path: path) else { return [] }
            meshes[path] = built
            return [built.vertices, built.indices]
        case let .ready(.texture(data)):
            let texture = textureLoader.texture(dds: data, usage: .color, label: path)
            textures[path] = texture
            return [texture]
        case let .failed(failure):
            failedPaths.append("\(path): \(failure)")
            return []
        case .loading, .ready:
            return []
        }
    }

    private func makeMesh(_ mesh: SkyMeshGeometry, path: String) -> Mesh? {
        guard let (vertexBuffer, indexBuffer) = mesh.geometry.makeBuffers(device: device) else {
            failedPaths.append("\(path): empty or not allocated")
            return nil
        }
        vertexBuffer.label = "SkyMeshVertices"
        indexBuffer.label = "SkyMeshIndices"
        return Mesh(vertices: vertexBuffer, indices: indexBuffer, shapes: mesh.shapes)
    }
}
