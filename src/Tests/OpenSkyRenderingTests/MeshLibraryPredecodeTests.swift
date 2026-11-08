// Parallel decode ahead of a build's loads: the loads must take the decodes and
// give the same result. Synthetic NIFs only (AGENTS.md Legal).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyRenderResources
import Testing

extension MeshLibraryTests {
    @Test(.enabled(if: Self.hasDevice)) func predecodeServesTheLoadsOfABuild() throws {
        let device = try #require(Self.device)
        let paths = (0 ..< 5).map { "meshes\\clutter\\cup\($0).nif" }
        for index in 0 ..< 5 {
            try writeLooseFile("meshes/clutter/cup\(index).nif", staticNIF())
        }
        try writeLooseFile("meshes/clutter/broken.nif", Data([1, 2, 3]))
        let library = try library(device: device)
        library.predecode(paths: paths + ["meshes\\clutter\\broken.nif"])
        #expect(library.predecoded.count == 6)
        for path in paths {
            _ = try library.model(path: path)
        }
        #expect(throws: MeshLibraryError.self) {
            _ = try library.model(path: "meshes\\clutter\\broken.nif")
        }
        #expect(library.predecoded.isEmpty)
        #expect(library.loadedCount == 5)
        library.predecode(paths: paths)
        #expect(library.predecoded.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func preparseFeedsActorLoadsOnce() throws {
        let device = try #require(Self.device)
        let paths = (0 ..< 4).map { "meshes\\armor\\part\($0).nif" }
        for index in 0 ..< 4 {
            try writeLooseFile("meshes/armor/part\(index).nif", staticNIF())
        }
        let library = try library(device: device)
        library.preparse(paths: paths)
        #expect(library.preparsed.count == 4)
        for path in paths {
            _ = try library.loadActorModel(path: path, skeleton: nil).get()
        }
        library.dropPreparsed()
        library.preparse(paths: paths)
        #expect(library.preparsed.isEmpty)
        library.decodesInParallel = false
        library.evict(dropping: Set(library.drainTouchedKeys()))
        library.preparse(paths: paths)
        #expect(library.preparsed.isEmpty)
    }
}
