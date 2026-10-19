// The inventory preview's state: the mesh path it shows, the turn per tick, and the
// placement that centres and fits a model.

import Foundation
@testable import OpenSkyMenus
import simd
import Testing

struct InventoryItemPreviewTests {
    @Test func aRecordPathGainsTheMeshesFolder() {
        var preview = InventoryItemPreview()
        preview.show("Weapons\\Iron\\LongSword.nif")
        #expect(preview.modelPath == "meshes\\weapons\\iron\\longsword.nif")
        preview.show("meshes\\clutter\\bucket.nif")
        #expect(preview.modelPath == "meshes\\clutter\\bucket.nif")
        preview.show(nil)
        #expect(preview.modelPath == nil)
    }

    @Test func theModelTurnsWithTimeAndRestartsForANewOne() {
        var preview = InventoryItemPreview()
        preview.show("a.nif")
        preview.tick(now: 10)
        #expect(preview.yaw == 0)
        preview.tick(now: 10.1)
        #expect(abs(preview.yaw - InventoryItemPreview.turnRate * 0.1) < 0.0001)
        // A long stall turns no more than a quarter second.
        preview.tick(now: 100)
        #expect(abs(preview.yaw - InventoryItemPreview.turnRate * 0.35) < 0.0001)
        preview.show("b.nif")
        #expect(preview.yaw == 0)
    }

    @Test func thePlacementCentresAndFitsTheBounds() {
        let placement = InventoryItemPreview.placement(
            bounds: (min: SIMD3(10, 10, 10), max: SIMD3(14, 10, 10)), yaw: 0
        )
        let middle = placement * SIMD4<Float>(12, 10, 10, 1)
        let end = placement * SIMD4<Float>(14, 10, 10, 1)
        #expect(simd_distance(SIMD3(middle.x, middle.y, middle.z), InventoryItemPreview.centre)
            < 0.0001)
        #expect(abs(simd_distance(middle, end) - InventoryItemPreview.radius) < 0.0001)
    }
}
