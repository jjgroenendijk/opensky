// Faction memberships through the actor template chain. The chain walk is
// `ActorTemplateResolver`, so this join lives beside it, not in GameData.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension FactionStore {
    /// An actor's memberships after `useFactions` inheritance, joined to their records.
    /// `sourcePlugin` names the plugin the FormIDs belong to. A broken chain gives an
    /// empty list.
    public func memberships(
        ofBase base: FormID,
        resolver: ActorTemplateResolver,
        fromPlugin sourcePlugin: String
    ) -> [ResolvedFactionMembership] {
        guard let resolved = try? resolver.resolveFactions(base: base) else { return [] }
        return memberships(resolved.factions.value, fromPlugin: sourcePlugin)
    }
}
