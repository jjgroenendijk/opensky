// Spawned-reference fixtures for the cell-scene fixture: a world-state
// snapshot that holds one runtime-created object. The world suites and the M12
// acceptance suites build the same spawn.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import simd

extension CellSceneBuilderFixture {
    /// The exterior cell every spawn build targets.
    public static var spawnCell: CellSceneLocation {
        .exterior(CellCoordinate(x: 6, y: -2))
    }

    /// A snapshot holding one spawned object, keyed the way the store keys a
    /// runtime-created reference.
    public func spawnState(
        sequence: UInt64 = 1,
        base: UInt32,
        position: SIMD3<Float>,
        scale: Float = 1,
        count: Int32 = 1,
        location: CellSceneLocation? = nil,
        deltas extra: [WorldStateComponentKind: WorldStateComponentValue] = [:]
    ) -> WorldStateSnapshot {
        let location = location ?? Self.spawnCell
        var components = extra
        components[.spawn] = ReferenceSpawnState(
            base: FormID(base),
            location: location,
            placement: PlacedReference.Placement(position: position, rotation: .zero),
            scale: scale,
            count: count
        ).erased
        return WorldStateSnapshot(
            entries: [WorldStateSnapshotEntry(
                key: .generated(sequence),
                delta: ReferenceStateDelta(components: components, cell: location)
            )],
            nextGeneratedSequence: sequence + 1,
            sequence: 1
        )
    }
}
