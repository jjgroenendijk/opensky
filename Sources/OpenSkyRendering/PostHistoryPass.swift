// A screen effect traced in compute between the scene copy and the composite, blended
// with last frame, and optionally blurred: ambient occlusion and indirect light
// (docs/rendering/post-effects.md).

import Metal
import OpenSkyRenderResources
import OpenSkyShaderTypes

/// The kernel names of one pass and the formats of its targets.
struct PostHistoryKernels {
    let label: String
    let trace: String
    /// The horizontal and vertical blur, or nil to read the trace as it is.
    let blurs: (horizontal: String, vertical: String)?
    let historyFormat: MTLPixelFormat
    let resultFormat: MTLPixelFormat

    static let occlusion = Self(
        label: "Occlusion", trace: "occlusionTrace",
        blurs: ("occlusionBlurHorizontal", "occlusionBlurVertical"),
        historyFormat: .rg16Float, resultFormat: .r16Float
    )
    static let indirectLight = Self(
        label: "IndirectLight", trace: "indirectLightTrace", blurs: nil,
        historyFormat: .rgba16Float, resultFormat: .rgba16Float
    )
}

/// One pass's kernels, their binding table, and the targets they keep between frames.
public final class PostHistoryPass {
    let kernels: PostHistoryKernels
    let trace: MTLComputePipelineState
    let blurs: (horizontal: MTLComputePipelineState, vertical: MTLComputePipelineState)?
    let argumentTable: MTL4ArgumentTable
    /// The traced value and its depth per pixel; the two swap each frame.
    private var history: [MTLTexture] = []
    private var scratch: MTLTexture?
    private var blurred: MTLTexture?
    /// What the composite reads: the blurred trace, or the trace itself.
    private(set) var result: MTLTexture?
    private var current = 0
    /// The frame that last traced, so a skipped frame does not blend stale history.
    private var lastTracedFrame: Int?

    init(_ kernels: PostHistoryKernels, library: MTLLibrary, compiler: PipelineCache) throws {
        self.kernels = kernels
        trace = try Self.kernel(kernels.trace, library: library, compiler: compiler)
        blurs = try kernels.blurs.map {
            try (
                Self.kernel($0.horizontal, library: library, compiler: compiler),
                Self.kernel($0.vertical, library: library, compiler: compiler)
            )
        }
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
            let first = history.first, first.width == target.width,
            first.height == target.height, history.count == 2
        {
            return true
        }
        let old = history + [scratch, blurred].compactMap(\.self)
        let label = kernels.label
        guard
            let first = Self.target(target, kernels.historyFormat, label + "HistoryA"),
            let second = Self.target(target, kernels.historyFormat, label + "HistoryB")
        else { return false }
        var made = [first, second]
        if kernels.blurs != nil {
            guard
                let pass = Self.target(target, kernels.resultFormat, label + "BlurScratch"),
                let final = Self.target(target, kernels.resultFormat, label + "Result")
            else { return false }
            (scratch, blurred) = (pass, final)
            made += [pass, final]
        } else {
            (scratch, blurred) = (nil, nil)
        }
        old.forEach { residency.removeAllocation($0) }
        history = [first, second]
        made.forEach { residency.addAllocation($0) }
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

    /// Encodes the trace, and the two blurs when the pass has them, for `frame`.
    func encode(
        _ encoder: MTL4ComputeCommandEncoder,
        inputs: PostHistoryInputs,
        frame: Int
    ) {
        guard history.count == 2 else { return }
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
        result = traced
        if let blurs, let scratch, let blurred {
            table.setTexture(traced.gpuResourceID, index: PostComputeTextureIndex.history.rawValue)
            table.setTexture(traced.gpuResourceID, index: PostComputeTextureIndex.source.rawValue)
            table.setTexture(scratch.gpuResourceID, index: PostComputeTextureIndex.output.rawValue)
            dispatch(encoder, blurs.horizontal, size: traced)
            table.setTexture(scratch.gpuResourceID, index: PostComputeTextureIndex.source.rawValue)
            table.setTexture(blurred.gpuResourceID, index: PostComputeTextureIndex.output.rawValue)
            dispatch(encoder, blurs.vertical, size: traced)
            result = blurred
        }
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
struct PostHistoryInputs {
    let uniforms: UInt64
    let depth: MTLTexture
    let scene: MTLTexture
}
