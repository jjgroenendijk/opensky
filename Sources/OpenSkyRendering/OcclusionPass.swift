// Ambient occlusion in three compute passes between the scene copy and the composite:
// the trace with the game's contrast curve and blend over time, then the two blur
// passes. docs/rendering/post-effects.md#ambient-occlusion has the steps.

import Metal
import OpenSkyRenderResources
import OpenSkyShaderTypes

/// The occlusion kernels, their binding table, and the targets they keep between frames.
public final class OcclusionPassResources {
    let trace: MTLComputePipelineState
    let blurHorizontal: MTLComputePipelineState
    let blurVertical: MTLComputePipelineState
    let argumentTable: MTL4ArgumentTable
    /// Occlusion and camera distance per pixel (rg16Float); the two swap each frame.
    private var history: [MTLTexture] = []
    private var scratch: MTLTexture?
    /// The blurred occlusion the composite reads.
    private(set) var result: MTLTexture?
    private var current = 0
    /// The frame that last traced, so a skipped frame does not blend stale history.
    private var lastTracedFrame: Int?

    init(library: MTLLibrary, compiler: PipelineCache) throws {
        trace = try Self.kernel("occlusionTrace", library: library, compiler: compiler)
        blurHorizontal = try Self.kernel(
            "occlusionBlurHorizontal", library: library, compiler: compiler
        )
        blurVertical = try Self.kernel(
            "occlusionBlurVertical", library: library, compiler: compiler
        )
        let table = MTL4ArgumentTableDescriptor()
        table.maxBufferBindCount = BufferIndex.postEffectUniforms.rawValue + 1
        table.maxTextureBindCount = PostComputeTextureIndex.output.rawValue + 1
        argumentTable = try compiler.device.makeArgumentTable(descriptor: table)
    }

    private static func kernel(
        _ name: String,
        library: MTLLibrary,
        compiler: PipelineCache
    ) throws -> MTLComputePipelineState {
        let function = MTL4LibraryFunctionDescriptor()
        function.name = name
        function.library = library
        let descriptor = MTL4ComputePipelineDescriptor()
        descriptor.computeFunctionDescriptor = function
        descriptor.label = name
        return try compiler.makeComputePipelineState(descriptor: descriptor)
    }

    /// Whether last frame's trace is in the history; false after a resize or a gap.
    func historyHolds(frame: Int) -> Bool {
        lastTracedFrame == frame - 1 && history.count == 2
    }

    /// Makes the targets match `target`. False when a texture cannot be made.
    func prepare(matching target: MTLTexture, residency: MTLResidencySet) -> Bool {
        if
            let result, result.width == target.width, result.height == target.height,
            history.count == 2
        {
            return true
        }
        let old = history + [scratch, result].compactMap(\.self)
        guard
            let first = Self.target(target, .rg16Float, "OcclusionHistoryA"),
            let second = Self.target(target, .rg16Float, "OcclusionHistoryB"),
            let blurred = Self.target(target, .r16Float, "OcclusionBlurScratch"),
            let final = Self.target(target, .r16Float, "OcclusionResult")
        else { return false }
        old.forEach { residency.removeAllocation($0) }
        history = [first, second]
        (scratch, result) = (blurred, final)
        [first, second, blurred, final].forEach { residency.addAllocation($0) }
        residency.commit()
        lastTracedFrame = nil
        return true
    }

    private static func target(
        _ match: MTLTexture,
        _ format: MTLPixelFormat,
        _ label: String
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: match.width, height: match.height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let texture = match.device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    /// Encodes the trace and the two blurs after the scene copies, for `frame`.
    func encode(
        _ encoder: MTL4ComputeCommandEncoder,
        inputs: OcclusionInputs,
        frame: Int
    ) {
        guard history.count == 2, let scratch, let result else { return }
        let traced = history[current]
        let previous = history[1 - current]
        let table = argumentTable
        encoder.setArgumentTable(table)
        table.setAddress(inputs.uniforms, index: BufferIndex.postEffectUniforms.rawValue)
        table.setTexture(inputs.depth.gpuResourceID, index: PostComputeTextureIndex.depth.rawValue)
        table.setTexture(inputs.scene.gpuResourceID, index: PostComputeTextureIndex.scene.rawValue)
        table.setTexture(previous.gpuResourceID, index: PostComputeTextureIndex.history.rawValue)
        table.setTexture(traced.gpuResourceID, index: PostComputeTextureIndex.output.rawValue)
        dispatch(encoder, trace, size: traced)
        table.setTexture(traced.gpuResourceID, index: PostComputeTextureIndex.history.rawValue)
        table.setTexture(traced.gpuResourceID, index: PostComputeTextureIndex.source.rawValue)
        table.setTexture(scratch.gpuResourceID, index: PostComputeTextureIndex.output.rawValue)
        dispatch(encoder, blurHorizontal, size: traced)
        table.setTexture(scratch.gpuResourceID, index: PostComputeTextureIndex.source.rawValue)
        table.setTexture(result.gpuResourceID, index: PostComputeTextureIndex.output.rawValue)
        dispatch(encoder, blurVertical, size: traced)
        current = 1 - current
        lastTracedFrame = frame
    }

    /// One pass over every pixel; a barrier keeps the next pass behind it.
    private func dispatch(
        _ encoder: MTL4ComputeCommandEncoder,
        _ pipeline: MTLComputePipelineState,
        size: MTLTexture
    ) {
        encoder.setComputePipelineState(pipeline)
        encoder.dispatchThreads(
            threadsPerGrid: MTLSize(width: size.width, height: size.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        encoder.barrier(
            afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch,
            visibilityOptions: .device
        )
    }
}

/// What the trace reads: this frame's uniforms and the scene copies.
struct OcclusionInputs {
    let uniforms: UInt64
    let depth: MTLTexture
    let scene: MTLTexture
}
