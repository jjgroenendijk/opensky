// The fixture builders that need the Crime implementation.

import FeaturesTesting
@testable import OpenSkyCrime
@testable import OpenSkyWorldState

extension CrimeFixture {
    public static func crimeFactions() throws -> CrimeFactionResolver {
        try CrimeFactionResolver(locations: locationStore(), factions: factionStore())
    }

    public static func ownershipResolver() throws -> OwnershipResolver {
        try OwnershipResolver(factions: factionStore(), pluginName: pluginName)
    }

    /// A crime runtime over a fresh store and the fixture load order.
    @MainActor
    public static func runtime(store: WorldStateStore = WorldStateStore()) throws -> CrimeRuntime {
        try CrimeRuntime(store: store, factions: factionStore())
    }
}
