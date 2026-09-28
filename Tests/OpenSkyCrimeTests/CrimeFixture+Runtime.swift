// The fixture builders that need the Crime implementation. The rest of CrimeFixture
// is in OpenSkyCrimeTesting, which may import only the interface.

@testable import OpenSkyCrime
@testable import OpenSkyCrimeTesting
@testable import OpenSkyWorldState

extension CrimeFixture {
    static func crimeFactions() throws -> CrimeFactionResolver {
        try CrimeFactionResolver(locations: locationStore(), factions: factionStore())
    }

    static func ownershipResolver() throws -> OwnershipResolver {
        try OwnershipResolver(factions: factionStore(), pluginName: pluginName)
    }

    /// A crime runtime over a fresh store and the fixture load order.
    @MainActor
    static func runtime(store: WorldStateStore = WorldStateStore()) throws -> CrimeRuntime {
        try CrimeRuntime(store: store, factions: factionStore())
    }
}
