// Texture candidates: the shipped blocks, RGBA8, ASTC at six block sizes and
// four efforts, and the shipped blocks at half and quarter size. Each loads on
// the CPU path and through MTLIO.

import Foundation
import Metal
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

extension AssetFormatComparison {
    func measureTexture(_ entry: AssetSampleEntry) throws -> AssetMeasurement {
        let usage: TextureUsage = entry.role == .color ? .color : .data
        let source = try files.contents(forPath: entry.path)
        let original = try originalRow(entry, sourceBytes: source.count) {
            let (data, read) = try Self.timed { try files.contents(forPath: entry.path) }
            let (dds, decode) = try Self.timed { try DDSFile(data: data) }
            let (texture, upload) = try Self.timed {
                try textureLoader.upload(dds: dds, usage: usage, label: entry.path)
            }
            return Sample(
                timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: upload),
                memoryBytes: texture.allocatedSize
            )
        }
        let dds = try DDSFile(data: source)
        let shipped = try GPUTexturePayload.shipped(dds)
        let shippedTexture = try shipped.upload(device: device, source: shipped.bytes)
        let levels = try shipped.levels.indices.map { level in
            try readback.pixels(of: shippedTexture, level: level)
        }
        var rows = [original]
        for candidate in try textureCandidates(dds: dds, shipped: shipped, levels: levels) {
            let payload = candidate.payload
            let fidelity = try textureFidelity(payload, reference: levels[0], role: entry.role)
            rows += cacheRows(
                candidate: candidate.name, payload: payload.bytes, convertMS: candidate.convertMS,
                paths: [.cpu, .mtlio], fidelity: fidelity
            ) { path, url, storage in
                try loadTexture(payload, url: url, storage: storage, path: path)
            }
        }
        return AssetMeasurement(
            entry: entry,
            detail: "\(dds.width)x\(dds.height) \(dds.format), \(dds.mipCount) mips",
            candidates: rows
        )
    }

    /// Each candidate with the milliseconds its conversion took.
    private func textureCandidates(
        dds: DDSFile,
        shipped: GPUTexturePayload,
        levels: [TexturePixels]
    ) throws -> [TextureCandidate] {
        var candidates = [TextureCandidate(name: "shipped", payload: shipped, convertMS: 0)]
        func add(_ name: String, _ build: () throws -> GPUTexturePayload) throws {
            let (payload, convertMS) = try Self.timed(build)
            candidates.append(TextureCandidate(name: name, payload: payload, convertMS: convertMS))
        }
        try add("rgba8") { try .rgba8(levels: levels) }
        for block in ASTCBlockSize.square {
            try add("astc\(block.width)x\(block.height)") {
                try .astc(levels: levels, block: block, effort: .medium)
            }
        }
        let effortBlock = ASTCBlockSize(width: 6, height: 6)
        for effort in [ASTCEffort.fastest, .fast, .thorough] {
            try add("astc6x6-\(effort.rawValue)") {
                try .astc(levels: levels, block: effortBlock, effort: effort)
            }
        }
        for (name, dropped) in [("shippedHalf", 1), ("shippedQuarter", 2)]
            where dds.mipCount > dropped
        {
            try add(name) { try .shipped(dds, droppedLevels: dropped) }
        }
        return candidates
    }

    /// Level 0 of the candidate against the shipped level 0, as the GPU decodes both.
    private func textureFidelity(
        _ payload: GPUTexturePayload,
        reference: TexturePixels,
        role: TextureRole?
    ) throws -> AssetFidelity {
        let texture = try payload.upload(device: device, source: payload.bytes)
        let pixels = payload.width == reference.width && payload.height == reference.height
            ? try readback.pixels(of: texture, level: 0)
            : try readback.pixels(of: texture, width: reference.width, height: reference.height)
        let difference = try TextureImageDifference.compare(
            reference: reference, candidate: pixels, normals: role == .normal
        )
        return AssetFidelity(exact: difference.isLossless, image: difference)
    }

    private func loadTexture(
        _ payload: GPUTexturePayload,
        url: URL,
        storage: AssetFileStorage,
        path: AssetLoadPath
    ) throws -> Sample {
        let texture: MTLTexture
        let timing: AssetLoadTiming
        if path == .mtlio {
            let (loaded, read) = try Self.timed {
                let texture = try payload.makeEmptyTexture(device: device)
                try io.load(url, storage: storage, layout: payload, into: texture)
                return texture
            }
            texture = loaded
            timing = AssetLoadTiming(readMS: read, decodeMS: 0, uploadMS: 0)
        } else {
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: payload.bytes.count)
            }
            let (loaded, upload) = try Self
                .timed { try payload.upload(device: device, source: data) }
            texture = loaded
            timing = AssetLoadTiming(readMS: read, decodeMS: 0, uploadMS: upload)
        }
        return Sample(
            timing: timing,
            memoryBytes: texture.allocatedSize,
            mismatch: Self.textureMismatch(texture, payload)
        )
    }

    private static func textureMismatch(
        _ texture: MTLTexture,
        _ payload: GPUTexturePayload
    ) -> String? {
        for (index, level) in payload.levels.enumerated() {
            var loaded = Data(count: level.length)
            loaded.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                texture.getBytes(
                    base,
                    bytesPerRow: level.bytesPerRow,
                    from: MTLRegionMake2D(0, 0, level.width, level.height),
                    mipmapLevel: index
                )
            }
            if loaded != payload.bytes.subdata(in: level.offset ..< level.offset + level.length) {
                return "loaded texels differ from the cache payload at level \(index)"
            }
        }
        return nil
    }
}

private struct TextureCandidate {
    let name: String
    let payload: GPUTexturePayload
    let convertMS: Double
}
