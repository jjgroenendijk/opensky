// The frame half of texture streaming. At the start of each frame it maps tiles for
// new and raised textures, copies their levels in, and unmaps levels it lowered a few
// frames ago. Draws bind a view that starts at the resident level, so the sampler never
// reads an unmapped level. See docs/rendering/texture-streaming.md.

import Metal
import OpenSkyAssetCache

/// What the Texture Streaming readout shows.
nonisolated public struct TextureStreamingStats: Equatable, Sendable {
    public var streamedTextures = 0
    /// Heap memory the pool holds.
    public var reservedBytes = 0
    /// Heap memory mapped to texture levels.
    public var usedBytes = 0
    public var budgetBytes = 0
    public var pendingReads = 0
    /// Levels copied in and levels dropped since launch.
    public var levelsLoaded = 0
    public var levelsDropped = 0

    public init() {}
}

/// One streamed texture. Levels `residentLevel` and smaller are mapped.
final class StreamedTextureEntry {
    weak var texture: MTLTexture?
    let source: TextureStreamSource
    let layout: SparseTextureLayout
    var residentLevel: Int
    /// Mapped tiles by level; the tail sits under `layout.firstLevelInTail`.
    var tiles: [Int: [SparseTile]] = [:]
    var view: MTLTexture?
    /// The first level of a read in flight.
    var requestedLevel: Int?
    /// Set while lowered levels wait for frames in flight before they unmap.
    var unmapAfterFrame: UInt64?
    var unmapLevels: Range<Int> = 0 ..< 0

    init(texture: MTLTexture, source: TextureStreamSource, layout: SparseTextureLayout) {
        self.texture = texture
        self.source = source
        self.layout = layout
        residentLevel = layout.mipCount
    }

    /// The texture a draw binds: a view of the resident levels.
    func binding(for texture: MTLTexture) -> MTLTexture {
        if let view {
            return view
        }
        guard residentLevel < layout.mipCount else { return texture }
        view = texture.makeTextureView(
            pixelFormat: texture.pixelFormat, textureType: .type2D,
            levels: residentLevel ..< layout.mipCount, slices: 0 ..< 1
        )
        return view ?? texture
    }
}

/// A copy of staged levels into a texture, encoded before the frame's passes.
struct StreamedTextureUpload {
    let texture: MTLTexture
    let levels: TextureLevelBytes
    let copyLevels: Range<Int>
}

public struct TextureStreamingState {
    public let mailbox = TextureStreamMailbox()
    /// Reads levels again; without one, textures keep the levels they started with.
    public var reader: (any TextureLevelReading)?
    let pool: SparseTilePool
    var entries: [ObjectIdentifier: StreamedTextureEntry] = [:]
    public var budgetBytes = 512 << 20
    /// The frame target's height, for the distance rule.
    var viewHeight = 1080
    var staging: [(frame: UInt64, buffers: [MTLBuffer])] = []
    public internal(set) var stats = TextureStreamingStats()

    init(device: MTLDevice) {
        pool = SparseTilePool(device: device, pageSize: TextureStreamingLoadSettings().pageSize)
    }

    /// New large textures stream while this is on. Off raises every streamed texture to
    /// its full size.
    public var enabled: Bool {
        get { mailbox.loadSettings.enabled }
        set { mailbox.loadSettings.enabled = newValue }
    }
}

extension Renderer {
    /// The texture a draw binds for `texture`: itself, or the view of a streamed one.
    func streamedBinding(_ texture: MTLTexture) -> MTLResourceID {
        guard
            !textureStreaming.entries.isEmpty,
            let entry = textureStreaming.entries[ObjectIdentifier(texture)]
        else { return texture.gpuResourceID }
        return entry.binding(for: texture).gpuResourceID
    }

    /// Runs once per frame after `beginCommandBuffer`, before any pass.
    func encodeTextureStreaming(target: MTL4RenderPassDescriptor) {
        if let height = target.colorAttachments[0].texture?.height {
            textureStreaming.viewHeight = height
        }
        releaseFinishedStaging()
        unmapLoweredLevels()
        dropDeadEntries()
        var uploads: [StreamedTextureUpload] = []
        for seed in textureStreaming.mailbox.drainSeeds() {
            if let upload = admit(seed) {
                uploads.append(upload)
            }
        }
        for delivery in textureStreaming.mailbox.drainDeliveries() {
            if let upload = raise(delivery.texture, with: delivery.levels) {
                uploads.append(upload)
            }
        }
        if frameIndex % Self.textureStreamingInterval == 0 {
            updateStreamedLevels()
        }
        encodeStreamingUploads(uploads)
        refreshTextureStreamingStats()
    }

    private func admit(_ seed: StreamedTextureSeed) -> StreamedTextureUpload? {
        let entry = StreamedTextureEntry(
            texture: seed.texture, source: seed.source, layout: seed.layout
        )
        let start = max(seed.levels.firstLevel, 0)
        guard mapLevels(start ..< seed.layout.mipCount, of: entry, texture: seed.texture) else {
            return nil
        }
        entry.residentLevel = start
        textureStreaming.entries[ObjectIdentifier(seed.texture)] = entry
        return StreamedTextureUpload(
            texture: seed.texture, levels: seed.levels, copyLevels: seed.levels.levels
        )
    }

    private func raise(_ texture: MTLTexture, with levels: TextureLevelBytes)
        -> StreamedTextureUpload?
    {
        guard let entry = textureStreaming.entries[ObjectIdentifier(texture)] else { return nil }
        entry.requestedLevel = nil
        let wanted = min(levels.firstLevel, entry.residentLevel) ..< entry.residentLevel
        guard
            !wanted.isEmpty, entry.unmapAfterFrame == nil,
            mapLevels(wanted, of: entry, texture: texture)
        else { return nil }
        entry.residentLevel = wanted.lowerBound
        entry.view = nil
        textureStreaming.stats.levelsLoaded += wanted.count
        return StreamedTextureUpload(texture: texture, levels: levels, copyLevels: wanted)
    }

    /// Lowers `entry` to `level`. The view changes now; the tiles unmap once the frames
    /// that still use the old view finish.
    func lower(_ entry: StreamedTextureEntry, to level: Int) {
        let target = min(level, entry.layout.floorLevel)
        guard target > entry.residentLevel, entry.unmapAfterFrame == nil else { return }
        entry.unmapLevels = entry.residentLevel ..< target
        entry.unmapAfterFrame = UInt64(frameIndex)
        entry.residentLevel = target
        entry.view = nil
        textureStreaming.stats.levelsDropped += entry.unmapLevels.count
    }

    /// Maps tiles for `levels`; the tail counts as one level. False when the pool is out
    /// of memory, with nothing mapped.
    private func mapLevels(
        _ levels: Range<Int>, of entry: StreamedTextureEntry, texture: MTLTexture
    ) -> Bool {
        let layout = entry.layout
        let tiled = levels.filter { $0 < layout.firstLevelInTail && entry.tiles[$0] == nil }
        let needsTail = levels.upperBound > layout.firstLevelInTail
            && entry.tiles[layout.firstLevelInTail] == nil && layout.tailTiles > 0
        let count = tiled.reduce(needsTail ? layout.tailTiles : 0) { $0 + layout.tiles(level: $1) }
        guard count > 0 else { return true }
        guard
            let tiles = textureStreaming.pool.allocate(count, added: { heap in
                residencySet.addAllocation(heap)
                residencySet.commit()
            }) else { return false }
        var remaining = tiles[...]
        var operations: [(heap: Int, operation: MTL4UpdateSparseTextureMappingOperation)] = []
        for level in tiled {
            let grid = layout.tileGrid(level: level)
            let levelTiles = Array(remaining.prefix(grid.x * grid.y))
            remaining = remaining.dropFirst(levelTiles.count)
            entry.tiles[level] = levelTiles
            for (offset, tile) in levelTiles.enumerated() {
                let region = MTLRegionMake2D(offset % grid.x, offset / grid.x, 1, 1)
                operations.append((tile.heap, .init(
                    mode: .map, textureRegion: region, textureLevel: level,
                    textureSlice: 0, heapOffset: tile.index
                )))
            }
        }
        if needsTail {
            let tailTiles = Array(remaining.prefix(layout.tailTiles))
            entry.tiles[layout.firstLevelInTail] = tailTiles
            for (offset, tile) in tailTiles.enumerated() {
                operations.append((tile.heap, .init(
                    mode: .map, textureRegion: MTLRegionMake2D(offset, 0, 1, 1),
                    textureLevel: layout.firstLevelInTail, textureSlice: 0,
                    heapOffset: tile.index
                )))
            }
        }
        for (heapID, group) in Dictionary(grouping: operations, by: \.heap) {
            commandQueue.updateMappings(
                texture: texture, heap: textureStreaming.pool.heap(heapID),
                operations: group.map(\.operation)
            )
        }
        return true
    }

    private func unmapLoweredLevels() {
        let drained = endFrameEvent.signaledValue
        for entry in textureStreaming.entries.values {
            guard let frame = entry.unmapAfterFrame, frame <= drained else { continue }
            entry.unmapAfterFrame = nil
            let levels = entry.unmapLevels.filter { $0 < entry.layout.firstLevelInTail }
            if let texture = entry.texture {
                let operations = levels.map { level in
                    let grid = entry.layout.tileGrid(level: level)
                    return MTL4UpdateSparseTextureMappingOperation(
                        mode: .unmap, textureRegion: MTLRegionMake2D(0, 0, grid.x, grid.y),
                        textureLevel: level, textureSlice: 0, heapOffset: 0
                    )
                }
                if !operations.isEmpty {
                    commandQueue.updateMappings(texture: texture, heap: nil, operations: operations)
                }
            }
            freeTiles(levels.flatMap { entry.tiles.removeValue(forKey: $0) ?? [] })
        }
    }

    /// A texture nobody holds can no longer be sampled, so its tiles return to the pool.
    private func dropDeadEntries() {
        let dead = textureStreaming.entries.filter { $0.value.texture == nil }
        for (key, entry) in dead {
            textureStreaming.entries[key] = nil
            freeTiles(entry.tiles.values.flatMap(\.self))
        }
    }

    private func freeTiles(_ tiles: [SparseTile]) {
        guard !tiles.isEmpty else { return }
        let emptied = textureStreaming.pool.free(tiles)
        retireAllocations(emptied)
    }

    private func encodeStreamingUploads(_ uploads: [StreamedTextureUpload]) {
        guard !uploads.isEmpty, let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        encoder.label = "Texture Streaming"
        encoder.barrier(
            afterQueueStages: .resourceState, beforeStages: .blit, visibilityOptions: .device
        )
        var buffers: [MTLBuffer] = []
        for upload in uploads {
            guard let buffer = stagingBuffer(upload.levels) else { continue }
            buffers.append(buffer)
            copy(upload, from: buffer, encoder: encoder)
        }
        encoder.barrier(
            afterStages: .blit, beforeQueueStages: [.vertex, .fragment, .dispatch],
            visibilityOptions: .device
        )
        encoder.endEncoding()
        residencySet.addAllocations(buffers)
        residencySet.commit()
        textureStreaming.staging.append((UInt64(frameIndex), buffers))
    }

    private func stagingBuffer(_ levels: TextureLevelBytes) -> MTLBuffer? {
        levels.ready.bytes.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap {
                device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
            }
        }
    }

    private func copy(
        _ upload: StreamedTextureUpload, from buffer: MTLBuffer,
        encoder: MTL4ComputeCommandEncoder
    ) {
        let ready = upload.levels.ready
        for level in upload.copyLevels where upload.levels.levels.contains(level) {
            let local = level - upload.levels.firstLevel
            let range = ready.levelRange(local)
            encoder.copy(
                sourceBuffer: buffer, sourceOffset: range.lowerBound,
                sourceBytesPerRow: ready.bytesPerRow(level: local),
                sourceBytesPerImage: range.count,
                sourceSize: MTLSize(
                    width: ready.width(level: local), height: ready.height(level: local), depth: 1
                ),
                destinationTexture: upload.texture, destinationSlice: 0,
                destinationLevel: level, destinationOrigin: MTLOrigin()
            )
        }
    }

    private func releaseFinishedStaging() {
        let drained = endFrameEvent.signaledValue
        let finished = textureStreaming.staging.filter { $0.frame <= drained }
        guard !finished.isEmpty else { return }
        textureStreaming.staging.removeAll { $0.frame <= drained }
        for entry in finished {
            for buffer in entry.buffers {
                residencySet.removeAllocation(buffer)
            }
        }
        residencySet.commit()
    }

    private func refreshTextureStreamingStats() {
        var stats = textureStreaming.stats
        stats.streamedTextures = textureStreaming.entries.count
        stats.reservedBytes = textureStreaming.pool.reservedBytes
        stats.usedBytes = textureStreaming.pool.usedTiles * textureStreaming.pool.tileBytes
        stats.budgetBytes = textureStreaming.budgetBytes
        stats.pendingReads = textureStreaming.entries.values.count { $0.requestedLevel != nil }
        textureStreaming.stats = stats
    }
}
