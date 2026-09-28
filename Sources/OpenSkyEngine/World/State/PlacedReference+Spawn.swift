// A spawned object as the `PlacedReference` every consumer of placements reads.
// The reference shape lives with the parsers in OpenSkyFormatsESM; spawn state is
// runtime state.

import OpenSkyFormatsESM

nonisolated extension PlacedReference {
    public init(spawn: ReferenceSpawnState, formID: FormID) {
        self.init(
            spawnedBase: spawn.base,
            placement: spawn.placement,
            scale: spawn.scale,
            count: spawn.count,
            formID: formID
        )
    }
}
