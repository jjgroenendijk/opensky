// A cell's location: its XLCN link first, then the LCTN cell lists for an exterior.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

struct CellLocationResolverTests {
    @Test
    func linkWinsOverTheCellList() throws {
        let resolver = try Self.resolver()
        let scene = Self.scene(.exterior(CellCoordinate(x: 4, y: -20)), link: 0x30)

        #expect(resolver.location(of: scene) == Self.fort)
    }

    @Test
    func exteriorWithoutLinkUsesTheCellList() throws {
        let resolver = try Self.resolver()

        #expect(resolver.location(of: Self.scene(.exterior(CellCoordinate(x: 4, y: -20))))
            == ResolvedFormID(plugin: "Base.esm", objectID: 0x20))
        #expect(resolver.location(of: Self.scene(.exterior(CellCoordinate(x: 9, y: 9)))) == nil)
        #expect(resolver.location(of: Self.scene(.interior(FormID(0x40)))) == nil)
    }

    // MARK: - Fixtures

    private static let world: UInt32 = 0x3C
    private static let fort = ResolvedFormID(plugin: "Base.esm", objectID: 0x30)

    private static func resolver() throws -> CellLocationResolver {
        var data = ESMFixture.tes4(masters: [])
        data += ESMFixture.topGroup("LCTN", contents: [
            LocationFixture.recordBytes(0x20, "Town", cellLists: [
                .init("LCEC", worldspace: world, cells: [CellCoordinate(x: 4, y: -20)])
            ]),
            LocationFixture.recordBytes(0x30, "Fort")
        ].reduce(Data(), +))
        let file = try ESMFile(data: data)
        return CellLocationResolver(store: LocationStore(plugins: [("Base.esm", file)]))
    }

    private static func scene(_ location: CellSceneLocation, link: UInt32? = nil) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test", gridX: 0, gridY: 0,
                totalRefCount: 0, drawnRefCount: 0,
                unsupportedBaseSkipCount: 0, markerSkipCount: 0,
                modelFailureSkipCount: 0, malformedRefSkipCount: 0,
                modelCount: 0, textureCount: 0, missingTextureCount: 0
            ),
            bounds: nil,
            location: location,
            locationLink: link.map { FormID($0) },
            ownerPluginName: "Base.esm",
            worldspace: FormID(world)
        )
    }
}
