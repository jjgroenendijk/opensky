// Compiles the renderer's pipelines once per build of the app. The first launch
// captures each compiled binary and saves them as a Metal 4 archive; later launches
// load a pipeline from the archive and compile only what it lacks. See
// docs/rendering/pipeline-cache.md.

import Foundation
import Metal

/// What the cache did since the renderer was built.
nonisolated public struct PipelineCacheStats: Equatable, Sendable {
    public enum Archive: Equatable, Sendable {
        /// The cache is off, or has no file.
        case none
        /// No archive for this app build, OS, and GPU yet.
        case missing
        case loaded
        /// The file could not be read; it was deleted and every pipeline compiled.
        case unreadable
    }

    public var archive = Archive.none
    /// Pipelines the archive held.
    public var hits = 0
    /// Pipelines compiled because the archive lacked them.
    public var misses = 0
    /// Whether this launch wrote a new archive.
    public var saved = false

    public init() {}
}

/// Pipeline creation for the renderer: an archive lookup first, then a compile.
public final class PipelineCache {
    public let device: MTLDevice
    public let fileURL: URL?
    public private(set) var stats = PipelineCacheStats()
    let compiler: MTL4Compiler
    private let archive: (any MTL4Archive)?
    private let serializer: (any MTL4PipelineDataSetSerializer)?

    /// `fileURL` nil compiles every pipeline and saves nothing.
    public init(device: MTLDevice, fileURL: URL?) throws {
        self.device = device
        self.fileURL = fileURL
        let descriptor = MTL4CompilerDescriptor()
        if fileURL != nil {
            let serializerDescriptor = MTL4PipelineDataSetSerializerDescriptor()
            serializerDescriptor.configuration = .captureBinaries
            let serializer = device.makePipelineDataSetSerializer(descriptor: serializerDescriptor)
            descriptor.pipelineDataSetSerializer = serializer
            self.serializer = serializer
        } else {
            serializer = nil
        }
        compiler = try device.makeCompiler(descriptor: descriptor)
        (archive, stats.archive) = Self.openArchive(device: device, fileURL: fileURL)
    }

    private static func openArchive(
        device: MTLDevice,
        fileURL: URL?
    ) -> ((any MTL4Archive)?, PipelineCacheStats.Archive) {
        guard let fileURL else { return (nil, .none) }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return (nil, .missing)
        }
        // Metal crashes on a damaged archive instead of throwing, so only a file that
        // matches the checksum written beside it reaches Metal.
        guard
            PipelineCacheFolder.isIntact(fileURL),
            let archive = try? device.makeArchive(url: fileURL)
        else {
            PipelineCacheFolder.remove(fileURL)
            return (nil, .unreadable)
        }
        return (archive, .loaded)
    }

    /// A classic or a mesh render pipeline.
    public func makeRenderPipelineState(
        descriptor: MTL4PipelineDescriptor
    ) throws -> MTLRenderPipelineState {
        if let archive, let state = try? archive.makeRenderPipelineState(descriptor: descriptor) {
            stats.hits += 1
            return state
        }
        stats.misses += 1
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    public func makeComputePipelineState(
        descriptor: MTL4ComputePipelineDescriptor
    ) throws -> MTLComputePipelineState {
        if let archive, let state = try? archive.makeComputePipelineState(descriptor: descriptor) {
            stats.hits += 1
            return state
        }
        stats.misses += 1
        return try compiler.makeComputePipelineState(
            descriptor: descriptor, compilerTaskOptions: nil
        )
    }

    /// Writes the archive when every pipeline of this launch was compiled. The serializer
    /// holds only compiled pipelines, so an archive that missed some is deleted instead,
    /// and the next launch compiles and saves them all.
    public func saveIfNeeded() throws {
        guard let fileURL, let serializer, stats.misses > 0 else { return }
        guard stats.hits == 0 else {
            PipelineCacheFolder.remove(fileURL)
            return
        }
        try PipelineCacheFolder.prepare(for: fileURL)
        try serializer.serializeAsArchiveAndFlush(url: fileURL)
        try PipelineCacheFolder.writeChecksum(for: fileURL)
        stats.saved = true
    }
}
