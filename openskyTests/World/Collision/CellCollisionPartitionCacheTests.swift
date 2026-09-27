// Collision partition cache eviction over synthetic geometry only. The cache
// shares canonical model keys with MeshLibrary and NIFCollisionLibrary, so a
// departed cell's drop-set must remove only matching partition results.

@testable import opensky
import simd
import Testing

struct CellCollisionPartitionCacheTests {
    @Test
    func evictionDropsEveryShapeForRequestedModelOnly() {
        let firstShape = CellCollisionPartitionKey("meshes\\arch\\first.nif", 0, 0)
        let secondShape = CellCollisionPartitionKey("meshes\\arch\\first.nif", 1, 2)
        let survivor = CellCollisionPartitionKey("meshes\\arch\\second.nif", 0, 0)
        var cache = CellCollisionPartitionCache()

        _ = cache.partitions(key: firstShape, geometry: .sphere(radius: 1))
        _ = cache.partitions(
            key: secondShape,
            geometry: .box(halfExtents: SIMD3<Float>(repeating: 2))
        )
        _ = cache.partitions(key: survivor, geometry: .sphere(radius: 3))
        #expect(cache.count == 3)

        cache.evict(dropping: ["meshes\\arch\\first.nif"])

        #expect(cache.count == 1)
        #expect(!cache.contains(firstShape))
        #expect(!cache.contains(secondShape))
        #expect(cache.contains(survivor))
    }
}
