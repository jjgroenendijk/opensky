// The one fixture builder that needs the Factions implementation.

@testable import OpenSkyFactions
@testable import OpenSkyGameData

extension HostilityFixture {
    /// The derivation over one such load order.
    public static func derivation(
        relations: [Relation] = [],
        pairs: [Pair] = []
    ) throws -> HostilityDerivation {
        let file = try file(relations: relations, pairs: pairs)
        return HostilityDerivation(
            relations: FactionRelationIndex(
                store: FactionStore(plugins: [(pluginName, file)])
            ),
            relationships: RelationshipStore(plugins: [(pluginName, file)])
        )
    }
}
