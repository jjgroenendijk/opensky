// The faction and relationship condition functions. `GetFactionRelation` counts
// 0 Neutral, 1 Enemy, 2 Ally, 3 Friend, which is not the `XNAM` order, so the
// mapping is written case by case. Indices, return values, and the functions
// left out are in docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    public static func installFaction(_ registry: inout ConditionFunctionRegistry) {
        installMemberships(&registry)
        installRelations(&registry)
    }

    /// The three membership functions, all `ptFaction` on the run-on actor.
    private static func installMemberships(_ registry: inout ConditionFunctionRegistry) {
        // "Returns 1 if the calling actor is a member of the specified faction."
        // (<https://ck.uesp.net/wiki/GetInFaction>)
        registry.register(ConditionFunction(
            index: 71,
            name: "GetInFaction",
            parameter1: .formID
        ) { call in
            factionQuery(call, index: 71) { seam, actor, faction in
                seam.isMember(actor, of: faction).map(Self.isTrue)
            }
        })

        // "If the actor isn't in the faction ... this returns -1."
        // (<https://ck.uesp.net/wiki/GetFactionRank>) An untracked run-on stays
        // `.unavailableFactions`, so a streaming gap is not hidden as a real answer.
        registry.register(ConditionFunction(
            index: 73,
            name: "GetFactionRank",
            parameter1: .formID
        ) { call in
            factionQuery(call, index: 73) { seam, actor, faction in
                guard seam.profile(of: actor) != nil else { return nil }
                return Float(seam.rank(of: actor, in: faction) ?? -1)
            }
        })

        // <https://ck.uesp.net/wiki/GetFactionRankDifference>: parameter 1 is the
        // faction, parameter 2 the other actor. A non-member counts as -1, as in
        // `GetFactionRank`; the wiki states neither that nor the order, so both
        // follow the sibling function and the sentence's own wording.
        registry.register(ConditionFunction(
            index: 60,
            name: "GetFactionRankDifference",
            parameter1: .formID,
            parameter2: .formID
        ) { call in
            guard let other = parameterReference(call, call.parameter2) else {
                return .failure(.unresolvedParameter(60))
            }
            return factionQuery(call, index: 60) { seam, actor, faction in
                guard seam.profile(of: actor) != nil, seam.profile(of: other) != nil else {
                    return nil
                }
                let mine = Int(seam.rank(of: actor, in: faction) ?? -1)
                let theirs = Int(seam.rank(of: other, in: faction) ?? -1)
                return Float(mine - theirs)
            }
        })
    }

    /// The three pair functions: what two actors' factions make of each other,
    /// what the two actors are to each other, and whether one wants the other
    /// dead.
    private static func installRelations(_ registry: inout ConditionFunctionRegistry) {
        // "Returns value based on Friend/Ally/Neutral/Enemy relationship with
        // TargetActorRef: 0 = Neutral, 1 = Enemy, 2 = Ally, 3 = Friend."
        // (<https://ck.uesp.net/wiki/GetFactionRelation>)
        registry.register(ConditionFunction(
            index: 449,
            name: "GetFactionRelation",
            parameter1: .formID
        ) { call in
            actorPair(call, index: 449) { seam, actor, other in
                seam.factionReaction(of: actor, toward: other)
                    .map { Float(Self.factionRelationValue(of: $0)) }
            }
        })

        // "4 Lover ... -4 Archnemesis" (<https://ck.uesp.net/wiki/GetRelationshipRank>).
        // The parameter names the other side, usually the player. An unnamed pair is
        // `.unavailableFactions`, not 0, because 0 is the authored Acquaintance.
        registry.register(ConditionFunction(
            index: 403,
            name: "GetRelationshipRank",
            parameter1: .formID
        ) { call in
            actorPair(call, index: 403) { seam, actor, other in
                seam.relationshipRank(of: actor, toward: other).map(Float.init)
            }
        })

        // Index 719, `IsHostileToActor`, one `ptActor` parameter. The Creation Kit
        // wiki carries no page for it and neither does its Papyrus twin, so the
        // name and the signature are xEdit's and the semantics are this engine's
        // whole hostility derivation asked about the pair — which is the same
        // answer the combat loop acts on, rather than a second one written here.
        registry.register(ConditionFunction(
            index: 719,
            name: "IsHostileToActor",
            parameter1: .formID
        ) { call in
            actorPair(call, index: 719) { seam, actor, other in
                seam.isHostile(actor, toward: other).map(Self.isTrue)
            }
        })
    }

    /// The Creation Kit number `GetFactionRelation` answers with, which is not
    /// the `XNAM` word `ActorReaction` stores.
    public static func factionRelationValue(of reaction: ActorReaction) -> Int {
        switch reaction {
        case .neutral: 0
        case .enemy: 1
        case .ally: 2
        case .friend: 3
        }
    }

    /// One faction query: resolve parameter 1 onto a FACT the load order carries,
    /// resolve the run-on onto an actor, then let `read` answer.
    ///
    /// A nil from `read` is `.unavailableFactions` — the parameter and the run-on
    /// both resolved and the seam simply carries nothing about them.
    private static func factionQuery(
        _ call: ConditionCall,
        index: UInt16,
        read: (FactionConditionResolution, ReferenceKey, ReferenceKey) -> Float?
    ) -> Result<Float, ConditionFailure> {
        guard let parameter = call.parameter1 else {
            return .failure(.unresolvedParameter(index))
        }
        guard let faction = call.context.factions.key(of: parameter.asFormID) else {
            return .failure(.unavailableFactions)
        }
        return call.referenceKey().flatMap { actor in
            guard let value = read(call.context.factions, actor, faction) else {
                return .failure(.unavailableFactions)
            }
            return .success(value)
        }
    }

    /// One pair query: resolve parameter 1 and the run-on, then `read` the two.
    /// The run-on is the observer, because a relationship need not be symmetric.
    private static func actorPair(
        _ call: ConditionCall,
        index: UInt16,
        read: (FactionConditionResolution, ReferenceKey, ReferenceKey) -> Float?
    ) -> Result<Float, ConditionFailure> {
        guard let other = parameterReference(call) else {
            return .failure(.unresolvedParameter(index))
        }
        return call.referenceKey().flatMap { actor in
            guard let value = read(call.context.factions, actor, other) else {
                return .failure(.unavailableFactions)
            }
            return .success(value)
        }
    }
}
