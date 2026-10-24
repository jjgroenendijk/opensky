// Rendering performance: what each GPU performance feature
// costs and saves, without `Renderer`.

import Foundation
import OpenSkyRenderCore
import OpenSkyRenderResources

/// What the rendering performance readout reads.
nonisolated public struct RenderPerformanceSnapshot: Equatable, Sendable {
    public let renderTargets: RenderTargetMemory
    public let pipelineCache: PipelineCacheStats
    /// What the CPU path culled in the last frame.
    public let cpuCulling: CullCounts
    /// What the GPU path culled, a few frames late.
    public let gpuCulling: CullCounts
    public var textureStreaming = TextureStreamingStats()
    public var rayTracing = RayTracingAvailability.unavailable(
        reason: RayTracingAvailability.missingReason
    )
    public var rayTracedShadows = RayTracedShadowStats()
    public var upscaling = UpscaleStatus()
    public var frameInterpolation = FrameInterpolationStatus()
    public var meshShaderGrass = MeshShaderGrassStatus()
    public var roomCulling = RoomCullingReadout()

    public init(
        renderTargets: RenderTargetMemory = RenderTargetMemory(),
        pipelineCache: PipelineCacheStats = PipelineCacheStats(),
        cpuCulling: CullCounts = CullCounts(),
        gpuCulling: CullCounts = CullCounts()
    ) {
        self.renderTargets = renderTargets
        self.pipelineCache = pipelineCache
        self.cpuCulling = cpuCulling
        self.gpuCulling = gpuCulling
    }
}

/// What MetalFX upscaling did in the last frame.
nonisolated public struct UpscaleStatus: Equatable, Sendable {
    /// Nil while upscaling is off.
    public var inputSize: SIMD2<Int>?
    public var outputSize: SIMD2<Int>?
    /// History resets since launch: scene swaps, camera cuts, and size changes.
    public var upscaler = UpscalerKind.temporal
    public var historyResets = 0
    /// Why this GPU cannot upscale; nil when it can.
    public var unavailableReason: String?
    /// MetalFX is still building the scaler, so the scene draws at full size.
    public var buildingScaler = false

    public init(
        inputSize: SIMD2<Int>? = nil, outputSize: SIMD2<Int>? = nil,
        upscaler: UpscalerKind = .temporal, historyResets: Int = 0,
        unavailableReason: String? = nil, buildingScaler: Bool = false
    ) {
        self.upscaler = upscaler
        self.inputSize = inputSize
        self.outputSize = outputSize
        self.historyResets = historyResets
        self.unavailableReason = unavailableReason
        self.buildingScaler = buildingScaler
    }
}

/// Readout text for the Rendering Performance sections, kept apart from AppKit so the
/// wording is unit-testable.
nonisolated public enum RenderPerformanceReadout: Sendable {
    public static func renderTargetText(_ memory: RenderTargetMemory) -> String {
        var lines = ["Render targets: \(megabytes(memory.totalBytes))"]
        for entry in memory.entries {
            let value = entry.isMemoryless ? "memoryless" : megabytes(entry.bytes)
            lines.append("\(entry.name): \(value)")
        }
        return lines.joined(separator: "\n")
    }

    public static func upscalingText(scale: RenderScale, status: UpscaleStatus) -> String {
        if let reason = status.unavailableReason {
            return "Upscaling: unavailable\n\(reason)"
        }
        if scale.isOn, status.buildingScaler {
            return """
            Upscaling: \(scale.percent)%, \(status.upscaler)
            Building the MetalFX scaler; the scene draws at full size until it is ready
            History resets: \(status.historyResets)
            """
        }
        guard scale.isOn, let input = status.inputSize, let output = status.outputSize else {
            return "Upscaling: off\nHistory resets: \(status.historyResets)"
        }
        return """
        Upscaling: \(scale.percent)%, \(status.upscaler)
        Scene: \(input.x) x \(input.y)  Output: \(output.x) x \(output.y)
        History resets: \(status.historyResets)
        """
    }

    static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
