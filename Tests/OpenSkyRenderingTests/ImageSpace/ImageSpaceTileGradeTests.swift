// The image-space grade in tile memory against the grade through a color copy, the
// tone-mapping stage, and the render targets each one leaves behind. Needs Metal 4.

import EngineTesting
import Metal
@testable import OpenSkyRendering
import TagsTesting
import Testing

@Suite(.tags(.gpu))
@MainActor
struct ImageSpaceTileGradeTests {
    private static let size = 64

    private static var grade: ImageSpaceParameters {
        var parameters = ImageSpaceParameters()
        parameters.saturation = 0.4
        parameters.brightness = 0.7
        parameters.contrast = 1.3
        parameters.tint = SIMD4(0.9, 0.6, 0.3, 0.5)
        return parameters
    }

    private func makeRenderer(grade: ImageSpaceParameters) throws -> Renderer {
        let device = try #require(OffscreenRendererFixture.device)
        let renderer = try OffscreenRendererFixture.makeRenderer(
            device: device, width: Self.size, height: Self.size,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.imageSpace.baseline = BaselineImageSpace(sources: [], parameters: grade)
        return renderer
    }

    private func render(_ renderer: Renderer) throws -> [UInt8] {
        try OffscreenRendererFixture.render(renderer, width: Self.size, height: Self.size)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func theTileGradeMatchesTheCopyGrade() throws {
        let renderer = try makeRenderer(grade: Self.grade)
        let tile = try render(renderer)
        renderer.imageSpaceAlwaysSplits = true
        let copy = try render(renderer)
        let worst = zip(tile, copy).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, "tile and copy grades differ by up to \(worst)")

        let neutral = try render(makeRenderer(grade: .neutral))
        #expect(neutral != tile, "the grade changed no pixel")
    }

    /// A white point below the scene's brightest value lifts the frame; the eye reads
    /// the luminance the GPU summed once the frame slot comes round again.
    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func toneMappingMeasuresTheSceneAndChangesTheFrame() throws {
        var hdr = ImageSpaceParameters()
        hdr.hdr.white = 0.5
        hdr.hdr.eyeAdaptStrength = 15
        let renderer = try makeRenderer(grade: hdr)
        renderer.imageSpace.toneMapping.enabled = false
        let off = try render(renderer)
        renderer.imageSpace.toneMapping.enabled = true
        var mapped = off
        for _ in 0 ... Renderer.maxFramesInFlight {
            mapped = try render(renderer)
        }
        #expect(mapped != off, "tone mapping changed no pixel")
        #expect(renderer.imageSpace.toneMapping.eye.measuredLuminance != nil)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func onlyASplitGradeAllocatesStoredTargets() throws {
        let renderer = try makeRenderer(grade: Self.grade)
        _ = try render(renderer)
        let tile = renderer.renderTargetMemory()
        #expect(tile.entries.first { $0.name == "Scene depth" }?.isMemoryless == true)
        #expect(!tile.entries.contains { $0.name == "Grade copy" || $0.name == "Grade depth" })

        renderer.imageSpaceAlwaysSplits = true
        _ = try render(renderer)
        let split = renderer.renderTargetMemory()
        #expect((split.entries.first { $0.name == "Grade depth" }?.bytes ?? 0) > 0)
        #expect(split.totalBytes > tile.totalBytes)
    }

    @Test func theReadoutNamesMemorylessTargets() {
        let memory = RenderTargetMemory(entries: [
            RenderTargetEntry(name: "Shadow maps", bytes: 3 * 1_048_576, isMemoryless: false),
            RenderTargetEntry(name: "Scene depth", bytes: 0, isMemoryless: true)
        ])
        #expect(RenderPerformanceReadout.renderTargetText(memory) == """
        Render targets: 3.0 MB
        Shadow maps: 3.0 MB
        Scene depth: memoryless
        """)
    }
}
