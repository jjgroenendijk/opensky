// The material textures of a scene draw group, set on the argument table slot by slot.

import Metal
import OpenSkyRenderResources
import OpenSkyShaderTypes

extension Renderer {
    /// The texture each slot of the argument table holds while one run of group draws
    /// encodes, so a draw sets only the slots that change. Metal 4 copies the table's
    /// bindings at each draw, so a slot left alone keeps its texture for the next one.
    /// A run starts empty, because other passes set the same slots between runs.
    nonisolated struct BoundTextures {
        private var ids = [MTLResourceID?](repeating: nil, count: 32)

        /// True when `id` is new for the slot; the slot then holds it.
        mutating func changes(_ id: MTLResourceID, at index: Int) -> Bool {
            guard ids.indices.contains(index) else { return true }
            if let bound = ids[index], bound._impl == id._impl {
                return false
            }
            ids[index] = id
            return true
        }
    }

    /// The fragment declares every surface slot, so the diffuse fills a 2D slot and
    /// the black cube the environment slot when a material lacks the texture.
    func bindMaterialTextures(_ material: RenderMaterial, bound: inout BoundTextures) {
        let diffuse = streamedBinding(material.diffuse)
        func bind(_ id: MTLResourceID, _ index: TextureIndex) {
            if bound.changes(id, at: index.rawValue) {
                argumentTable.setTexture(id, index: index.rawValue)
            }
        }
        func bindSurface(_ texture: (any MTLTexture)?, _ index: TextureIndex) {
            if let texture {
                bind(streamedBinding(texture), index)
            } else {
                bind(diffuse, index)
            }
        }
        bind(diffuse, .diffuse)
        bind(material.effect?.palette?.gpuResourceID ?? diffuse, .effectPalette)
        let surface = material.surface
        bindSurface(material.normal, .surfaceNormal)
        bindSurface(surface.glow, .surfaceGlow)
        bindSurface(surface.detail, .surfaceDetail)
        bindSurface(surface.environmentMask, .surfaceEnvironmentMask)
        bindSurface(material.faceTint ?? surface.innerLayer, .surfaceLayer)
        bindSurface(surface.backLight, .surfaceBackLight)
        bindSurface(surface.projected?.diffuse, .projectedDiffuse)
        bindSurface(surface.projected?.noise, .projectedNoise)
        bind((surface.environment ?? blackCube).gpuResourceID, .surfaceEnvironment)
        bind((material.effect?.sourceVolume ?? greyVolume).gpuResourceID, .effectSourceVolume)
        bind(refraction.copy?.gpuResourceID ?? diffuse, .sceneColor)
    }
}
