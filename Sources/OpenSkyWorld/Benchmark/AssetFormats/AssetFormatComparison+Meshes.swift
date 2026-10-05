// Mesh candidates: the NIF stored loose (parsed at load), and the ready GPU
// buffers, which load on the CPU path or stream through MTLIO. Textures are a
// shared 1x1 stand-in, so only mesh work is timed.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

extension AssetFormatComparison {
    func measureMesh(_ entry: AssetSampleEntry) throws -> AssetMeasurement {
        let source = try files.contents(forPath: entry.path)
        let standIn = try standInTexture()
        let provider: TextureProvider = { _, _ in standIn }
        let original = try originalRow(entry, sourceBytes: source.count) {
            let (data, read) = try Self.timed { try files.contents(forPath: entry.path) }
            return try parseAndUpload(data, read: read, provider: provider)
        }
        let model = try NIFFile(data: source).model(skeleton: nil)
        let reference = try RenderModel(device: device, model: model, textureProvider: provider)
        let ready = ReadyMeshPayload(model: model)
        let expected = ReadyMeshPayload.bufferBytes(of: reference)
        let fidelity = try AssetFidelity(exact: ready.packed
            .blobs(from: ready.packed.bytes) == expected)
        let shippedRows = cacheRows(
            candidate: "shipped", payload: source, paths: [.cpu], fidelity: .lossless
        ) { _, url, storage in
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: source.count)
            }
            return try parseAndUpload(data, read: read, provider: provider)
        }
        let readyRows = cacheRows(
            candidate: "ready", payload: ready.packed.bytes, paths: [.cpu, .mtlio],
            fidelity: fidelity
        ) { path, url, storage in
            try loadReadyMesh(ready, url: url, storage: storage, path: path)
        }
        let vertices = model.meshes.map(\.positions.count).reduce(0, +)
        let triangles = model.meshes.map(\.indices.count).reduce(0, +) / 3
        return AssetMeasurement(
            entry: entry,
            detail: "\(model.meshes.count) meshes, \(vertices) vertices, \(triangles) triangles",
            candidates: [original] + shippedRows + readyRows
        )
    }

    private func parseAndUpload(
        _ data: Data,
        read: Double,
        provider: TextureProvider
    ) throws -> Sample {
        let (model, decode) = try Self.timed { try NIFFile(data: data).model(skeleton: nil) }
        let (render, upload) = try Self.timed {
            try RenderModel(device: device, model: model, textureProvider: provider)
        }
        let memory = render.meshes
            .flatMap { [$0.vertexBuffer, $0.indexBuffer, $0.skinningBuffer].compactMap(\.self) }
            .map(\.allocatedSize).reduce(0, +)
        return Sample(
            timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: upload),
            memoryBytes: memory
        )
    }

    private func loadReadyMesh(
        _ ready: ReadyMeshPayload,
        url: URL,
        storage: AssetFileStorage,
        path: AssetLoadPath
    ) throws -> Sample {
        let buffers: [MTLBuffer]
        let timing: AssetLoadTiming
        if path == .mtlio {
            let (loaded, read) = try Self.timed {
                let buffers = try ready.makeEmptyBuffers(device: device)
                try io.load(
                    url, storage: storage,
                    ranges: zip(buffers, ready.packed.ranges).map { ($0, $1.offset) }
                )
                return buffers
            }
            buffers = loaded
            timing = AssetLoadTiming(readMS: read, decodeMS: 0, uploadMS: 0)
        } else {
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: ready.packed.bytes.count)
            }
            let (loaded, upload) = try Self.timed { try ready.upload(device: device, source: data) }
            buffers = loaded
            timing = AssetLoadTiming(readMS: read, decodeMS: 0, uploadMS: upload)
        }
        let loadedBytes = buffers.map { Data(bytes: $0.contents(), count: $0.length) }
        let expected = try ready.packed.blobs(from: ready.packed.bytes)
        return Sample(
            timing: timing,
            memoryBytes: buffers.map(\.allocatedSize).reduce(0, +),
            mismatch: loadedBytes == expected ? nil : "loaded buffers differ from the cache payload"
        )
    }

    private func standInTexture() throws -> MTLTexture {
        let pixel = TexturePixels(width: 1, height: 1, rgba: [128, 128, 128, 255])
        let payload = try GPUTexturePayload.rgba8(levels: [pixel])
        return try payload.upload(device: device, source: payload.bytes)
    }
}
