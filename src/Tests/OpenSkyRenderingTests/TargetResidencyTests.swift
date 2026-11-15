// A replaced render target stays resident until the frames that may read it finish.
// Needs Metal 4.

import Metal
import OpenSkyEngineTesting
@testable import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
@MainActor
struct TargetResidencyTests {
    private static let size = 64

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aReplacedTargetLeavesTheResidencySetOnlyAfterAFrameFinishes() throws {
        let device = try #require(OffscreenRendererFixture.device)
        let renderer = try OffscreenRendererFixture.makeRenderer(
            device: device, width: Self.size, height: Self.size,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        let old = try #require(device.makeBuffer(length: 256, options: .storageModePrivate))
        let new = try #require(device.makeBuffer(length: 256, options: .storageModePrivate))
        renderer.residencySet.addAllocation(old)
        renderer.residencySet.commit()

        renderer.targetResidency.replace([old], with: [new])
        #expect(renderer.residencySet.containsAllocation(new))
        #expect(renderer.residencySet.containsAllocation(old))
        let retired = renderer.retired.flatMap(\.allocations).map(ObjectIdentifier.init)
        #expect(retired.contains(ObjectIdentifier(old)))

        _ = try renderer.renderOffscreen(width: Self.size, height: Self.size)
        #expect(!renderer.residencySet.containsAllocation(old))
        #expect(renderer.residencySet.containsAllocation(new))
    }
}
