// The seam for `Developer > Rendering Performance`: what each GPU performance feature
// costs and saves, without `Renderer`.

import Foundation

/// What the Rendering Performance panel reads.
nonisolated public struct RenderPerformanceSnapshot: Equatable, Sendable {
    public let renderTargets: RenderTargetMemory
    public let pipelineCache: PipelineCacheStats
    /// What the CPU path culled in the last frame.
    public let cpuCulling: CullCounts
    /// What the GPU path culled, a few frames late.
    public let gpuCulling: CullCounts

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

@MainActor
public protocol RenderPerformanceControlProviding: AnyObject {
    /// Nil without a renderer.
    var renderPerformanceSnapshot: RenderPerformanceSnapshot? { get }
    /// Applies on the next launch, because the renderer builds its pipelines once.
    var pipelineCacheEnabled: Bool { get set }
    /// Deletes the saved archives. Returns how many files it deleted.
    @discardableResult
    func clearPipelineCache() -> Int
    /// Culls the scene's static groups on the GPU. Off culls them on the CPU.
    var gpuCullingEnabled: Bool { get set }
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

    public static func pipelineCacheText(_ stats: PipelineCacheStats) -> String {
        let archive = switch stats.archive {
        case .none: "off"
        case .missing: "none yet"
        case .loaded: "loaded"
        case .unreadable: "unreadable, rebuilt"
        }
        return """
        Archive: \(archive)\(stats.saved ? ", saved" : "")
        Loaded: \(stats.hits)  Compiled: \(stats.misses)
        """
    }

    public static func cullingText(cpu: CullCounts, gpu: CullCounts) -> String {
        """
        Camera CPU: \(cpu.cameraVisible) drawn, \(cpu.cameraCulled) culled
        Camera GPU: \(gpu.cameraVisible) drawn, \(gpu.cameraCulled) culled
        Shadows CPU: \(cpu.shadowVisible) drawn, \(cpu.shadowCulled) culled
        Shadows GPU: \(gpu.shadowVisible) drawn, \(gpu.shadowCulled) culled
        """
    }

    static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
