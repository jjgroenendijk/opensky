// The player rig build reports a load order without the player's record as an error,
// both from the builder and through the build runner's provider.

import Foundation
import Metal
@testable import OpenSkyCells
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import Testing

struct CellSceneBuilderPlayerRigTests {
    private static let request = PlayerRigRequest(
        generation: 1, firstPerson: false, equipped: nil, appearance: nil
    )

    @Test(.enabled(if: CellSceneBuilderTests.hasDevice))
    func aLoadOrderWithoutThePlayerBuildsNoRig() throws {
        let fixtures = try CellSceneBuilderTests()
        let device = try #require(CellSceneBuilderTests.device)
        let builder = try fixtures.makeBuilder(pluginData: fixtures.plugin(), device: device)
        #expect(throws: PlayerBodyError.self) { try builder.assemblePlayerRig(Self.request).get() }
        let provider = BuilderCellSceneProvider(builder: builder, worldspaceEditorID: "Tamriel")
        #expect(throws: PlayerBodyError.self) { try provider.assemblePlayerRig(Self.request).get() }
    }
}
