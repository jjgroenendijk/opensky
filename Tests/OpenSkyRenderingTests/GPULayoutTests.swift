// Swift structs that the GPU reads must keep the byte layout the shaders expect.

@testable import OpenSkyRendering
import OpenSkyShaderTypes
import Testing

struct GPULayoutTests {
    @Test func particleInstanceMatchesShaderStruct() {
        typealias Host = MemoryLayout<ParticleGPUInstance>
        typealias Shader = MemoryLayout<ParticleInstance>
        #expect(Host.stride == Shader.stride)
        #expect(Host.offset(of: \.positionSize) == Shader.offset(of: \.positionSize))
        #expect(Host.offset(of: \.color) == Shader.offset(of: \.color))
        #expect(Host.offset(of: \.uvRect) == Shader.offset(of: \.uvRect))
    }

    @Test func skinVertexMatchesDescriptorOffsets() {
        typealias Host = MemoryLayout<SkinVertex>
        #expect(Host.offset(of: \.weights) == SkinVertexLayout.weightsOffset)
        #expect(Host.offset(of: \.boneIndices) == SkinVertexLayout.boneIndicesOffset)
    }
}
