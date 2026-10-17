// The MetalFX temporal upscaler's pipelines and targets. The scene renders into the
// input targets at the render scale; the scaler writes the output at the display size.
// See docs/rendering/upscaling.md.

import Metal
import MetalFX
import MetalKit
import OpenSkyShaderTypes

/// The motion and composite pipelines, built once with the renderer.
public final class UpscaleResources {
    let cameraMotion: MTLRenderPipelineState
    let staticMotion: MTLRenderPipelineState
    let skinnedMotion: MTLRenderPipelineState
    let composite: MTLRenderPipelineState
    /// Passes only where a moving surface is the visible one; writes no depth.
    let motionDepthState: MTLDepthStencilState
    let uniformBuffer: MTLBuffer
    /// Nil when the GPU has no Metal 4 temporal scaler.
    let temporalUnavailableReason: String?
    let spatialUnavailableReason: String?
    let interpolatorUnavailableReason: String?

    nonisolated static let motionFormat = MTLPixelFormat.rg16Float
    nonisolated static let outputFormat = MTLPixelFormat.rgba16Float
    static let uniformStride = (MemoryLayout<UpscaleMotionUniforms>.size + 0xFF) & -0x100

    init(view: MTKView, library: MTLLibrary, compiler: PipelineCache) throws {
        let device = compiler.device
        func make(
            _ recipe: (vertex: String, fragment: String),
            layout: MTLVertexDescriptor? = nil,
            format: MTLPixelFormat
        ) throws -> MTLRenderPipelineState {
            let vertex = MTL4LibraryFunctionDescriptor()
            vertex.library = library
            vertex.name = recipe.vertex
            let fragment = MTL4LibraryFunctionDescriptor()
            fragment.library = library
            fragment.name = recipe.fragment
            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = recipe.fragment
            descriptor.vertexFunctionDescriptor = vertex
            descriptor.fragmentFunctionDescriptor = fragment
            descriptor.vertexDescriptor = layout
            descriptor.colorAttachments[0].pixelFormat = format
            return try compiler.makeRenderPipelineState(descriptor: descriptor)
        }
        cameraMotion = try make(
            ("textureReadbackVertex", "cameraMotionFragment"), format: Self.motionFormat
        )
        staticMotion = try make(
            ("staticMotionVertex", "objectMotionFragment"),
            layout: StaticVertexLayout.vertexDescriptor(),
            format: Self.motionFormat
        )
        skinnedMotion = try make(
            ("skinnedMotionVertex", "objectMotionFragment"),
            layout: SkinVertexLayout.vertexDescriptor(),
            format: Self.motionFormat
        )
        composite = try make(
            ("textureReadbackVertex", "upscaleCompositeFragment"),
            format: view.colorPixelFormat
        )
        let depth = MTLDepthStencilDescriptor()
        depth.label = "MotionDepth"
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else {
            throw RendererError.depthStateAllocationFailed
        }
        motionDepthState = depthState
        uniformBuffer = try Renderer.makeUniformBuffer(
            device: device, length: Self.uniformStride * Renderer.maxFramesInFlight,
            label: "UpscaleMotionUniforms"
        )
        temporalUnavailableReason = MTLFXTemporalScalerDescriptor.supportsMetal4FX(device)
            ? nil : "This GPU has no MetalFX temporal scaler"
        spatialUnavailableReason = MTLFXSpatialScalerDescriptor.supportsMetal4FX(device)
            ? nil : "This GPU has no MetalFX spatial scaler"
        interpolatorUnavailableReason = FrameInterpolationSupport.unsupportedReason(device)
    }
}

/// One of the two MetalFX scalers.
nonisolated enum UpscaleScaler {
    case temporal(any MTL4FXTemporalScaler)
    case spatial(any MTL4FXSpatialScaler)
}

/// The sizes and formats one scaler build needs, as values that cross to the build task.
nonisolated struct UpscaleScalerRequest: Equatable, Sendable {
    let kind: UpscalerKind
    let input: SIMD2<Int>
    let output: SIMD2<Int>
    let colorFormat: MTLPixelFormat
    let interpolates: Bool
}

/// The input and output targets of one input and output size, and their scaler.
final class UpscaleTargets {
    let color: MTLTexture
    let depth: MTLTexture
    /// Only the temporal scaler reads motion.
    let motion: MTLTexture?
    /// The scaler writes here; with interpolation it swaps with `interpolation.history`.
    private(set) var output: MTLTexture
    let scaler: UpscaleScaler
    let interpolation: InterpolationTargets?
    /// What was asked for, with `interpolates` false when MetalFX refused the interpolator.
    let request: UpscaleScalerRequest

    var kind: UpscalerKind {
        if case .spatial = scaler {
            return .spatial
        }
        return .temporal
    }

    var inputSize: SIMD2<Int> {
        SIMD2(color.width, color.height)
    }

    var outputSize: SIMD2<Int> {
        SIMD2(output.width, output.height)
    }

    var allocations: [MTLAllocation] {
        [color, depth, motion, output].compactMap(\.self) + (interpolation?.allocations ?? [])
    }

    /// Keeps this frame's scaler output as the interpolator's previous frame.
    func swapInterpolationHistory() {
        guard let interpolation else { return }
        (output, interpolation.history) = (interpolation.history, output)
        interpolation.historyValid = true
    }

    init(
        _ request: UpscaleScalerRequest,
        scaler: UpscaleScaler,
        interpolator: (any MTL4FXFrameInterpolator)?,
        device: MTLDevice
    ) throws {
        let (input, outputSize, colorFormat) = (request.input, request.output, request.colorFormat)
        let usage: (color: MTLTextureUsage, output: MTLTextureUsage)
        var readUsage = MTLTextureUsage.shaderRead
        switch scaler {
        case let .temporal(temporal):
            usage = (temporal.colorTextureUsage, temporal.outputTextureUsage)
            readUsage = temporal.depthTextureUsage.union(temporal.motionTextureUsage)
            if let interpolator {
                readUsage.formUnion(
                    interpolator.depthTextureUsage.union(interpolator.motionTextureUsage)
                )
                // Metal 4 tracks no hazards: the interpolator reads the scaler's output.
                let fence = device.makeFence()
                temporal.fence = fence
                interpolator.fence = fence
            }
        case let .spatial(spatial):
            usage = (spatial.colorTextureUsage, spatial.outputTextureUsage)
        }
        self.scaler = scaler
        self.request = UpscaleScalerRequest(
            kind: request.kind, input: input, output: outputSize, colorFormat: colorFormat,
            interpolates: interpolator != nil
        )
        let kind = request.kind
        func texture(
            _ format: MTLPixelFormat, _ size: SIMD2<Int>, _ usage: MTLTextureUsage, _ label: String
        ) throws -> MTLTexture {
            try Self.privateTexture(
                device: device, format: format, size: size, usage: usage, label: label
            )
        }
        color = try texture(colorFormat, input, [.renderTarget, usage.color], "UpscaleInputColor")
        depth = try texture(
            .depth32Float_stencil8, input, [.renderTarget, readUsage], "UpscaleInputDepth"
        )
        motion = kind == .temporal
            ? try texture(
                UpscaleResources.motionFormat, input, [.renderTarget, readUsage], "UpscaleMotion"
            )
            : nil
        let outputFormat = kind == .spatial ? colorFormat : UpscaleResources.outputFormat
        let outputUsage = usage.output.union(.shaderRead)
            .union(interpolator?.colorTextureUsage ?? [])
        output = try texture(outputFormat, outputSize, outputUsage, "UpscaleOutput")
        interpolation = try interpolator.map { interpolator in
            try InterpolationTargets(
                interpolator: interpolator,
                history: texture(outputFormat, outputSize, outputUsage, "UpscaleOutputHistory"),
                frame: texture(
                    outputFormat, outputSize, interpolator.outputTextureUsage.union(.shaderRead),
                    "InterpolatedFrame"
                )
            )
        }
    }

    static func privateTexture(
        device: MTLDevice, format: MTLPixelFormat, size: SIMD2<Int>, usage: MTLTextureUsage,
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size.x, height: size.y, mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.upscalerUnavailable
        }
        texture.label = label
        return texture
    }
}
