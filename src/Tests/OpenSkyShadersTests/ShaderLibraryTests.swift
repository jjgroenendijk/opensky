// The module's resource bundle carries the compiled shaders.

import Foundation
import Metal
@testable import OpenSkyShaders
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct ShaderLibraryTests {
    @Test func bundleHoldsTheCompiledLibrary() throws {
        let url = try #require(ShaderLibrary.url)
        #expect(url.lastPathComponent == "default.metallib")
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func libraryLoadsWithItsFunctions() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try ShaderLibrary.make(device: device)
        #expect(!library.functionNames.isEmpty)
    }

    @Test func missingLibraryNamesTheBundle() {
        #expect(ShaderLibrary.LoadError.missing.description.contains("OpenSkyShaders"))
    }
}
