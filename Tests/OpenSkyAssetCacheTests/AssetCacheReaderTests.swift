// The read path with a fake file source: hit, miss, stale, corrupt, and off.

import Foundation
@testable import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyGameData
import Testing

private struct StampedFiles: GameFileSource {
    var stamps: [String: GameFileProvenance]

    func exists(_ path: String) -> Bool {
        provenance(forPath: path) != nil
    }

    func contents(forPath path: String) throws -> Data {
        throw VFSError.fileNotFound(path: path)
    }

    func archiveEntries() -> [VFSEntry] {
        []
    }

    func fileNames(inDirectory _: String) -> [String] {
        []
    }

    func provenance(forPath path: String) -> GameFileProvenance? {
        (try? VirtualFileSystem.normalize(path)).flatMap { stamps[$0] }
    }
}

struct AssetCacheReaderTests {
    private let path = "textures\\rock.dds"
    private let meshPath = "meshes\\rock.nif"
    private let provenance = GameFileProvenance(origin: "a.bsa", size: 10, modified: 5)
    private let decoder = AssetCacheDecoder(
        kind: .texture,
        converterVersion: AssetConverterVersion.texture
    ) { data in
        guard data.first != 0xFF else { throw CachePayloadError.truncated }
        return Array(data)
    }

    private func makeReader(provenance: GameFileProvenance? = nil) throws -> AssetCacheReader {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "AssetCacheReaderTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let store = try AssetCacheStore(root: root, limitBytes: 1 << 30)
        let stamp = provenance ?? self.provenance
        let files = StampedFiles(stamps: [path: stamp, meshPath: stamp])
        return AssetCacheReader(store: store, files: files)
    }

    private func store(
        _ payload: [UInt8],
        in reader: AssetCacheReader,
        converter: UInt32 = AssetConverterVersion.texture
    ) throws {
        let source = try #require(reader.stamp(forPath: "Textures/Rock.dds"))
        try reader.store.store(Data(payload), for: AssetCacheRequest(
            kind: .texture, source: source, converterVersion: converter
        ))
    }

    @Test func aCurrentEntryIsUsed() throws {
        let reader = try makeReader()
        try store([1, 2], in: reader)
        #expect(reader.value(forPath: "Textures/Rock.dds", decoder: decoder) == [1, 2])
        #expect(reader.counts(for: .texture).hits == 1)
    }

    @Test func aMissLoadsTheOriginal() throws {
        let reader = try makeReader()
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture).misses == 1)
        #expect(reader.takeRebuildItems().isEmpty)
    }

    @Test func aStaleEntryIsDroppedAndMarkedForRebuild() throws {
        let reader = try makeReader()
        try store([1], in: reader, converter: 1)
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture).stale == 1)
        #expect(reader.takeRebuildItems() == [AssetCacheRebuildItem(kind: .texture, path: path)])
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture).misses == 1)
    }

    @Test func aPayloadThatDoesNotDecodeIsDroppedAndMarkedForRebuild() throws {
        let reader = try makeReader()
        try store([0xFF], in: reader)
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture).unreadable == 1)
        #expect(reader.takeRebuildItems().count == 1)
    }

    @Test func aCacheTurnedOffAlwaysLoadsTheOriginal() throws {
        let reader = try makeReader()
        try store([1], in: reader)
        reader.isEnabled = false
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture) == AssetCacheReadCounts())
    }

    @Test func aKindTurnedOffLoadsTheOriginalAndKeepsItsEntry() throws {
        let reader = try makeReader()
        try store([1], in: reader)
        reader.kinds = [.mesh]
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture) == AssetCacheReadCounts())
        reader.kinds.insert(.texture)
        #expect(reader.value(forPath: path, decoder: decoder) == [1])
    }

    @Test func anotherTextureQualityMakesTheTextureStale() throws {
        let reader = try makeReader()
        try store([1], in: reader)
        reader.textureOutput = AssetTextureOutput(quality: .low)
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture).stale == 1)
    }

    @Test func anEmptyEntryLoadsTheOriginalWithoutARebuild() throws {
        let reader = try makeReader()
        try store([], in: reader)
        #expect(reader.value(forPath: path, decoder: decoder) == nil)
        #expect(reader.counts(for: .texture).original == 1)
        #expect(reader.takeRebuildItems().isEmpty)
    }

    @Test func aModelLayoutReadsOnlyTheEntryHead() throws {
        let reader = try makeReader()
        let meshes = (0 ..< 3).map {
            ReadyModelLayoutTests.quad(name: "M\($0)", offset: Float($0), vertices: 2000)
        }
        let model = Model(meshes: meshes, materials: [.fallback], skippedShapeCount: 0)
        let payload = ModelCacheCodec.encode(model)
        let source = try #require(reader.stamp(forPath: meshPath))
        let request = AssetCacheRequest(
            kind: .mesh, source: source, converterVersion: AssetConverterVersion.mesh
        )
        try reader.store.store(payload, for: request)

        let entry = try #require(reader.modelLayout(forPath: meshPath))
        #expect(try entry.value == (ModelCacheCodec.decodeLayout(payload)))
        let file = try Data(contentsOf: entry.file)
        let first = try #require(entry.value.meshes.first)
        let start = entry.payloadOffset + first.vertexRange.lowerBound
        #expect(file[start ..< start + first.vertexRange.count] == payload[first.vertexRange])
        guard
            case let .hit(hit) = reader.store.lookupHead(request, payloadHead: {
                ModelCacheCodec.layoutByteCount(head: $0)
            })
        else {
            Issue.record("no hit")
            return
        }
        #expect(hit.file.count < file.count)
        #expect(reader.counts(for: .mesh).hits == 1)
    }

    @Test func inspectionReportsEachEntryState() throws {
        let reader = try makeReader()
        #expect(reader.inspect(path: path) == [AssetCacheEntryInspection(
            kind: .texture,
            state: .missing
        )])
        try store([1, 2, 3], in: reader, converter: AssetConverterVersion.texture)
        #expect(reader.inspect(path: path) == [
            AssetCacheEntryInspection(kind: .texture, state: .current(payloadBytes: 3))
        ])
        try store([], in: reader, converter: AssetConverterVersion.texture)
        #expect(reader.inspect(path: path)?.first?.state == .original)
        #expect(reader.inspect(path: "textures\\none.dds") == nil)
    }
}
