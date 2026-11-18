// An `XOWN` actor owner names an `NPC_` base, not a placed actor, so its faction
// list comes from the record. See docs/engine/crime.md, Prices and flags.

public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// The factions an `NPC_` record authors, keyed the way the session keys factions.
nonisolated public struct AuthoredFactions: Sendable {
    public let baselines: ActorFactionBaselineResolver
    /// The plugin namespace the baselines read FormIDs in.
    public let pluginName: String

    public init(baselines: ActorFactionBaselineResolver, pluginName: String) {
        self.baselines = baselines
        self.pluginName = pluginName
    }

    /// The `SNAM` run of the base `key` names, through its template chain. Empty for a
    /// key that is no `NPC_` record.
    public func memberships(ofBase key: ReferenceKey, factions: FactionStore) -> ActorFactionState {
        guard let base = factions.localFormID(of: key, inPlugin: pluginName) else {
            return ActorFactionState()
        }
        return baselines.baseline(for: base).memberships.reduce(ActorFactionState()) {
            guard let faction = factions.resolve($1.faction, fromPlugin: pluginName) else {
                return $0
            }
            return $0.joining(ReferenceKey(resolved: faction.id), rank: $1.rank)
        }
    }
}
