// The faction and relationship condition functions (issue #508, roadmap item
// 21.4), split out of `ConditionFunctions` the way the actor, crime, data, magic
// and perk families are.
//
// Six functions, from the xEdit TES5 condition table
// (dev-4.1.6 Core/wbDefinitionsTES5.pas):
//
//   (Index:  60; Name: 'GetFactionRankDifference'; ParamType1: ptFaction; ParamType2: ptActor)
//   (Index:  71; Name: 'GetInFaction'; ParamType1: ptFaction)
//   (Index:  73; Name: 'GetFactionRank'; ParamType1: ptFaction)
//   (Index: 403; Name: 'GetRelationshipRank'; ParamType1: ptReference)
//   (Index: 449; Name: 'GetFactionRelation'; ParamType1: ptActor)
//   (Index: 719; Name: 'IsHostileToActor'; ParamType1: ptActor)
//
// The indices are the raw stored numbers; the Creation Kit spells each 4096
// higher.
//
// ## Two numbering systems that are not the same
//
// `GetFactionRelation` returns "0 = Neutral, 1 = Enemy, 2 = Ally, 3 = Friend"
// (<https://ck.uesp.net/wiki/GetFactionRelation>), and the Papyrus counterpart
// `GetFactionReaction` lists the same four in the same order. That is *not* the
// order the `XNAM` combat-reaction word uses, which `ActorReaction` carries as
// Ally 0, Friend 1, Neutral 2, Enemy 3. Mapping between the two is written out
// case by case below rather than done with arithmetic, because the two tables
// come from different sources and nothing guarantees they stay related.
//
// A second disagreement, between the console function and its Papyrus twin:
// `GetFactionRank` "returns -1" for an actor not in the faction
// (<https://ck.uesp.net/wiki/GetFactionRank>), while `Actor.GetFactionRank`
// returns "-2 if the Actor is not in the faction" and reserves -1 for a member
// whose rank really is -1
// (<https://ck.uesp.net/wiki/GetFactionRank_-_Actor>). Both are implemented as
// documented, which is why this file and `PapyrusNativeFaction.swift` spell the
// same question two ways.
//
// ## What is deliberately not installed
//
// `GetIsInFactionList` does not exist. The xEdit table carries no function of
// that name at any index; the list-shaped sibling is `IsInList` (index 372,
// `ptFormList`), which is about the run-on's *base object* rather than about
// memberships, and it belongs with the M18 data family rather than here.
//
// The five `GetPC*` faction functions (193, 195, 197, 199 and 132) are absent
// because the state behind them is: expulsion, faction murder and faction attack
// are player-versus-faction bookkeeping no component in this engine records, and
// registering them over the membership list would answer every one of them
// "no" — a convincing wrong answer rather than a measurable gap. `ConditionTally`
// counts them by index, which is what the real-data sweep ranks the next
// implementation from.
//
// Documented in docs/engine/condition-functions.md and docs/engine/hostility.md.

import Foundation
import OpenSkyFormats

nonisolated extension ConditionFunctions {
    static func installFaction(_ registry: inout ConditionFunctionRegistry) {
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

        // "Returns the actor's rank in the faction. If the actor isn't in the
        // faction, or if the run-on reference isn't actually an actor, then this
        // returns -1." (<https://ck.uesp.net/wiki/GetFactionRank>)
        //
        // Only the first half of that sentence is answered with -1 here. A run-on
        // that names no actor this session tracks has no profile, and reporting
        // it as "in no faction" would hide a streaming gap behind a real answer,
        // so it stays `.unavailableFactions`.
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

        // "Returns the difference in rank between the current actor and target
        // actor in the specified faction."
        // (<https://ck.uesp.net/wiki/GetFactionRankDifference>) Parameter 1 is
        // the faction and parameter 2 is the other actor, in that order.
        //
        // A non-member counts as the same -1 `GetFactionRank` reports, so the
        // difference between a rank-2 member and an outsider is 3. The wiki
        // states neither the non-member value nor the subtraction order for this
        // function; the order is the sentence's own ("the current actor and
        // target actor") and the value is its sibling's, which is the closest
        // documented thing to a rule.
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

        // "Returns the actor's relationship rank with the player", over the table
        // "4 Lover ... -4 Archnemesis"
        // (<https://ck.uesp.net/wiki/GetRelationshipRank>). The parameter names
        // the other side, so the player is only the usual argument rather than
        // the only one.
        //
        // A pair no `RELA` record and no script names is `.unavailableFactions`
        // rather than 0: 0 is Acquaintance, a rank vanilla authors deliberately.
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
    static func factionRelationValue(of reaction: ActorReaction) -> Int {
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

    /// One pair query: resolve parameter 1 onto a second reference, resolve the
    /// run-on, then let `read` answer about the two of them.
    ///
    /// The direction is the run-on's, as it is for the detection family:
    /// `[Observer].IsHostileToActor Target` asks what the observer makes of the
    /// target, and reversing it would answer about the wrong actor everywhere a
    /// relationship is not symmetric.
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
