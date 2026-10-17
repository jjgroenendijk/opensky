// MetalFX builds the temporal scaler and the frame interpolator through the Neural Engine
// compiler, a system service. A first build takes seconds, and the service can stop
// answering, so the build runs off the main actor and the frame draws at full size until
// it lands. See docs/rendering/upscaling.md.

import Metal
import MetalFX

/// The MetalFX objects one request built. A nil scaler means MetalFX refused it.
nonisolated struct UpscaleScalers {
    let scaler: UpscaleScaler?
    let interpolator: (any MTL4FXFrameInterpolator)?

    @concurrent
    static func buildOffMainActor(
        _ request: UpscaleScalerRequest, device: MTLDevice, compiler: MTL4Compiler
    ) async -> sending Self {
        build(request, device: device, compiler: compiler)
    }

    /// Blocks until MetalFX has compiled its model, so the frame loop never calls it.
    static func build(
        _ request: UpscaleScalerRequest, device: MTLDevice, compiler: MTL4Compiler
    ) -> sending Self {
        switch request.kind {
        case .temporal:
            guard let scaler = temporalScaler(request, device: device, compiler: compiler) else {
                return Self(scaler: nil, interpolator: nil)
            }
            let interpolator = request.interpolates
                ? frameInterpolator(request, device: device, compiler: compiler) : nil
            return Self(scaler: .temporal(scaler), interpolator: interpolator)
        case .spatial:
            let scaler = spatialScaler(request, device: device, compiler: compiler)
            return Self(scaler: scaler.map(UpscaleScaler.spatial), interpolator: nil)
        }
    }

    private static func temporalScaler(
        _ request: UpscaleScalerRequest, device: MTLDevice, compiler: MTL4Compiler
    ) -> (any MTL4FXTemporalScaler)? {
        let descriptor = MTLFXTemporalScalerDescriptor()
        descriptor.colorTextureFormat = request.colorFormat
        descriptor.depthTextureFormat = .depth32Float_stencil8
        descriptor.motionTextureFormat = UpscaleResources.motionFormat
        descriptor.outputTextureFormat = UpscaleResources.outputFormat
        descriptor.inputWidth = request.input.x
        descriptor.inputHeight = request.input.y
        descriptor.outputWidth = request.output.x
        descriptor.outputHeight = request.output.y
        return descriptor.makeTemporalScaler(device: device, compiler: compiler)
    }

    private static func spatialScaler(
        _ request: UpscaleScalerRequest, device: MTLDevice, compiler: MTL4Compiler
    ) -> (any MTL4FXSpatialScaler)? {
        let descriptor = MTLFXSpatialScalerDescriptor()
        // The spatial scaler rejects an sRGB input with a non-sRGB output.
        descriptor.colorTextureFormat = request.colorFormat
        descriptor.outputTextureFormat = request.colorFormat
        descriptor.inputWidth = request.input.x
        descriptor.inputHeight = request.input.y
        descriptor.outputWidth = request.output.x
        descriptor.outputHeight = request.output.y
        descriptor.colorProcessingMode = .perceptual
        return descriptor.makeSpatialScaler(device: device, compiler: compiler)
    }

    private static func frameInterpolator(
        _ request: UpscaleScalerRequest, device: MTLDevice, compiler: MTL4Compiler
    ) -> (any MTL4FXFrameInterpolator)? {
        let descriptor = MTLFXFrameInterpolatorDescriptor()
        descriptor.colorTextureFormat = UpscaleResources.outputFormat
        descriptor.outputTextureFormat = UpscaleResources.outputFormat
        descriptor.depthTextureFormat = .depth32Float_stencil8
        descriptor.motionTextureFormat = UpscaleResources.motionFormat
        descriptor.inputWidth = request.input.x
        descriptor.inputHeight = request.input.y
        descriptor.outputWidth = request.output.x
        descriptor.outputHeight = request.output.y
        return descriptor.makeFrameInterpolator(device: device, compiler: compiler)
    }
}

/// One scaler build: in flight until `scalers` is set, then waiting for a frame to take it.
final class UpscaleScalerBuild {
    let request: UpscaleScalerRequest
    var scalers: UpscaleScalers?
    var task: Task<Void, Never>?

    init(request: UpscaleScalerRequest) {
        self.request = request
    }
}

extension Renderer {
    /// Waits for the scaler build in flight. The next frame then takes the scaler.
    public func upscalerBuildFinished() async {
        await upscale.scalerBuild?.task?.value
    }

    /// Builds the scaler for an offscreen frame of this size now, blocking the caller.
    /// For tools that render frames in a loop and never give the main actor a turn.
    public func buildUpscalerNow(width: Int, height: Int) {
        guard upscale.renderScale.isOn, upscale.unavailableReason == nil else { return }
        let request = upscaleScalerRequest(
            output: SIMD2(width, height), colorFormat: Self.offscreenColorFormat
        )
        if upscale.targets?.request == request {
            return
        }
        if let build = upscale.scalerBuild, build.request == request, build.scalers != nil {
            return
        }
        let build = UpscaleScalerBuild(request: request)
        build.scalers = UpscaleScalers.build(
            request, device: pipelineCache.device, compiler: pipelineCache.compiler
        )
        upscale.scalerBuild = build
    }

    func upscaleScalerRequest(
        output: SIMD2<Int>, colorFormat: MTLPixelFormat
    ) -> UpscaleScalerRequest {
        UpscaleScalerRequest(
            kind: upscale.upscaler,
            input: upscale.renderScale.inputSize(width: output.x, height: output.y),
            output: output,
            colorFormat: colorFormat,
            interpolates: wantsFrameInterpolation
        )
    }

    /// The built scalers for `request`; nil while their build runs, and the first call
    /// starts it. The frame draws at full size until they arrive.
    func takeBuiltScalers(for request: UpscaleScalerRequest) -> UpscaleScalers? {
        if let build = upscale.scalerBuild, build.request == request {
            guard let scalers = build.scalers else { return nil }
            upscale.scalerBuild = nil
            return scalers
        }
        let build = UpscaleScalerBuild(request: request)
        let (device, compiler) = (pipelineCache.device, pipelineCache.compiler)
        build.task = Task { [build] in
            build.scalers = await UpscaleScalers.buildOffMainActor(
                request, device: device, compiler: compiler
            )
        }
        upscale.scalerBuild = build
        return nil
    }
}
