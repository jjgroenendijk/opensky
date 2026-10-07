// The seam for `Developer > Rendering Performance`: what each GPU performance feature
// costs and saves, without `Renderer`.

import Foundation

/// What the Rendering Performance panel reads.
nonisolated public struct RenderPerformanceSnapshot: Equatable, Sendable {
    public let renderTargets: RenderTargetMemory

    public init(renderTargets: RenderTargetMemory = RenderTargetMemory()) {
        self.renderTargets = renderTargets
    }
}

@MainActor
public protocol RenderPerformanceControlProviding: AnyObject {
    /// Nil without a renderer.
    var renderPerformanceSnapshot: RenderPerformanceSnapshot? { get }
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

    static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
