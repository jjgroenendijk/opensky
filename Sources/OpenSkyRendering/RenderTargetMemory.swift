// The render targets the renderer owns and what each one costs in GPU memory. A
// memoryless target lives in tile memory only, so it costs nothing.

import Metal

/// One render target of the frame.
nonisolated public struct RenderTargetEntry: Equatable, Sendable {
    public let name: String
    /// Zero for a memoryless target.
    public let bytes: Int
    public let isMemoryless: Bool

    public init(name: String, bytes: Int, isMemoryless: Bool) {
        self.name = name
        self.bytes = bytes
        self.isMemoryless = isMemoryless
    }

    init(texture: MTLTexture, name: String) {
        let memoryless = texture.storageMode == .memoryless
        self.init(
            name: name,
            bytes: memoryless ? 0 : texture.allocatedSize,
            isMemoryless: memoryless
        )
    }
}

/// The frame's render targets. A target that does not exist is left out.
nonisolated public struct RenderTargetMemory: Equatable, Sendable {
    public let entries: [RenderTargetEntry]

    public init(entries: [RenderTargetEntry] = []) {
        self.entries = entries
    }

    public var totalBytes: Int {
        entries.reduce(0) { $0 + $1.bytes }
    }
}

extension Renderer {
    /// The last scene depth, the shadow cascades, the scratch targets of a split
    /// image-space grade, and the upscaler's targets. The drawables belong to the view and are not
    /// counted.
    public func renderTargetMemory() -> RenderTargetMemory {
        let owned: [(String, MTLTexture?)] = [
            ("Shadow maps", shadow.map),
            ("Grade copy", imageSpacePass.sceneCopy),
            ("Grade depth", imageSpacePass.storedDepth),
            ("Upscale color", upscale.targets?.color),
            ("Upscale depth", upscale.targets?.depth),
            ("Upscale motion", upscale.targets?.motion),
            ("Upscale output", upscale.targets?.output)
        ]
        let entries = owned.compactMap { name, texture in
            texture.map { RenderTargetEntry(texture: $0, name: name) }
        }
        return RenderTargetMemory(entries: [lastSceneDepth].compactMap(\.self) + entries)
    }
}
