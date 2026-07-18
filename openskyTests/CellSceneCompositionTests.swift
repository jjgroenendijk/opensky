// CellSceneComposition: resident-cell bookkeeping + recomposition into one
// RenderScene. Pure value tests run device-free on empty scenes; the
// compose-count test uploads tiny synthetic models (RenderSceneTests
// pattern) and is device-gated.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct CellSceneCompositionTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static func emptyCellScene(
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil
    ) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "test",
                gridX: 0,
                gridY: 0,
                totalRefCount: 0,
                drawnRefCount: 0,
                unsupportedBaseSkipCount: 0,
                markerSkipCount: 0,
                modelFailureSkipCount: 0,
                malformedRefSkipCount: 0,
                modelCount: 0,
                textureCount: 0,
                missingTextureCount: 0
            ),
            bounds: bounds
        )
    }

    @Test func addRemoveTracksCountsAndCoordinates() {
        var composition = CellSceneComposition()
        #expect(composition.cellCount == 0)
        #expect(composition.coordinates.isEmpty)

        composition.setCell(Self.emptyCellScene(), at: CellCoordinate(x: 6, y: -2))
        composition.setCell(Self.emptyCellScene(), at: CellCoordinate(x: 7, y: -2))
        #expect(composition.cellCount == 2)
        #expect(composition.coordinates == [
            CellCoordinate(x: 6, y: -2), CellCoordinate(x: 7, y: -2)
        ])

        // Re-setting a coordinate replaces, never duplicates.
        composition.setCell(Self.emptyCellScene(), at: CellCoordinate(x: 6, y: -2))
        #expect(composition.cellCount == 2)

        let removed = composition.removeCell(at: CellCoordinate(x: 6, y: -2))
        #expect(removed != nil)
        #expect(composition.cellCount == 1)
        #expect(composition.coordinates == [CellCoordinate(x: 7, y: -2)])
        #expect(composition.removeCell(at: CellCoordinate(x: 0, y: 0)) == nil)
    }

    @Test func composedBoundsUnionsResidentCells() {
        var composition = CellSceneComposition()
        #expect(composition.composedBounds() == nil)

        composition.setCell(
            Self.emptyCellScene(bounds: (SIMD3(0, 0, 0), SIMD3(10, 10, 10))),
            at: CellCoordinate(x: 0, y: 0)
        )
        // A cell that drew nothing contributes no bounds.
        composition.setCell(Self.emptyCellScene(), at: CellCoordinate(x: 1, y: 0))
        composition.setCell(
            Self.emptyCellScene(bounds: (SIMD3(-5, 2, 0), SIMD3(4, 20, 3))),
            at: CellCoordinate(x: 0, y: 1)
        )
        let bounds = composition.composedBounds()
        #expect(bounds?.min == SIMD3(-5, 0, 0))
        #expect(bounds?.max == SIMD3(10, 20, 10))
    }

    @Test(.enabled(if: Self.hasDevice)) func recomposeReflectsAddAndRemove() throws {
        let device = try #require(Self.device)
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 1
        descriptor.height = 1
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = .shaderRead
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let mesh = Mesh(
            name: nil,
            transform: matrix_identity_float4x4,
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            normals: [],
            tangents: [],
            bitangents: [],
            uvs: [],
            colors: [],
            indices: [0, 1, 2],
            materialSlot: 0
        )
        let model = Model(meshes: [mesh], materials: [.fallback], skippedShapeCount: 0)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }

        func cell(instances: Int) -> CellScene {
            let placements = (0 ..< instances).map { index in
                RenderPlacement(
                    model: render,
                    transform: MatrixMath.translation(SIMD3(Float(index) * 8, 0, 0))
                )
            }
            let template = Self.emptyCellScene()
            return CellScene(
                renderScene: RenderScene(instances: placements),
                summary: template.summary,
                bounds: template.bounds
            )
        }

        var composition = CellSceneComposition()
        composition.setCell(cell(instances: 2), at: CellCoordinate(x: 0, y: 0))
        composition.setCell(cell(instances: 3), at: CellCoordinate(x: 1, y: 0))
        #expect(composition.composedScene().drawCount == 5)

        composition.removeCell(at: CellCoordinate(x: 0, y: 0))
        #expect(composition.composedScene().drawCount == 3)

        composition.setCell(cell(instances: 1), at: CellCoordinate(x: 2, y: 0))
        #expect(composition.composedScene().drawCount == 4)

        composition.removeCell(at: CellCoordinate(x: 1, y: 0))
        composition.removeCell(at: CellCoordinate(x: 2, y: 0))
        #expect(composition.composedScene().drawCount == 0)
    }
}
