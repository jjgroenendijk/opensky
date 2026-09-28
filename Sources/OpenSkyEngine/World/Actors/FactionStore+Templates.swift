// Faction memberships through the actor template chain. The chain walk is
// `ActorTemplateResolver`, so this join lives beside it, not in GameData.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension FactionStore {
    /// An actor's memberships after `useFactions` template inheritance, each
    /// joined to the faction record.
    ///
    /// The chain walk is `ActorTemplateResolver`'s, which indexes one plugin by
    /// raw FormID, so `sourcePlugin` names the plugin those FormIDs belong to.
    /// A chain that cannot be walked — a dangling TPLT, a cycle, an empty
    /// leveled list — yields an empty list rather than throwing: a caller
    /// asking who an actor sides with wants an answer it can act on, and the
    /// resolver's own suites cover the failure modes.
    public func memberships(
        ofBase base: FormID,
        resolver: ActorTemplateResolver,
        fromPlugin sourcePlugin: String
    ) -> [ResolvedFactionMembership] {
        guard let resolved = try? resolver.resolveFactions(base: base) else { return [] }
        return memberships(resolved.factions.value, fromPlugin: sourcePlugin)
    }
}
