// Relationship-record and hostility condition functions, indices from xEdit
// wbDefinitionsTES5.pas: 66 GetShouldAttack, 132 GetPCInFaction, 258
// HasAssociationType, 259 HasFamilyRelationship, 261 HasParentRelationship, 616
// GetLowestRelationshipRank, 638 IsInFriendStateWithPlayer, 652
// GetInSharedCrimeFaction, 678 ShouldAttackKill. See
// docs/engine/condition-functions-world.md#relationships.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension ConditionFunctions {
    /// The `ParentChild` association type, which gives `parent` and `child` a direction.
    static let parentChildAssociation = "ParentChild"

    static func installRelationshipRecords(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 132, name: "GetPCInFaction", parameter1: .formID
        ) { call in
            factionQuery(call, index: 132) { seam, _, faction in
                seam.isMember(.player, of: faction).map(Self.isTrue)
            }
        })
        // OpenSky has no brawl, so every attack is to kill.
        for (index, name) in [(UInt16(66), "GetShouldAttack"), (678, "ShouldAttackKill")] {
            registry.register(ConditionFunction(
                index: index, name: name, parameter1: .formID
            ) { call in
                actorPair(call, index: index) { seam, actor, other in
                    seam.isHostile(actor, toward: other).map(Self.isTrue)
                }
            })
        }
        registry.register(ConditionFunction(
            index: 638, name: "IsInFriendStateWithPlayer"
        ) { call in
            call.referenceKey().flatMap { actor in
                guard call.context.factions.profile(of: actor) != nil else {
                    return .failure(.unavailableFactions)
                }
                let rank = call.context.factions.relationshipRank(of: actor, toward: .player)
                return .success(Self.isTrue((rank ?? 0) >= 1))
            }
        })
        registry.register(ConditionFunction(
            index: 652, name: "GetInSharedCrimeFaction", parameter1: .formID
        ) { call in
            actorPair(call, index: 652) { seam, actor, other in
                guard let mine = seam.profile(of: actor), let theirs = seam.profile(of: other)
                else { return nil }
                return Self
                    .isTrue(mine.crimeFaction != nil && mine.crimeFaction == theirs.crimeFaction)
            }
        })
        installRelationshipRecordQueries(&registry)
    }

    private static func installRelationshipRecordQueries(
        _ registry: inout ConditionFunctionRegistry
    ) {
        registry.register(ConditionFunction(
            index: 258, name: "HasAssociationType", parameter1: .formID, parameter2: .formID
        ) { call in
            guard let wanted = call.parameter2 else { return .failure(.unresolvedParameter(258)) }
            return relationshipRecord(call, index: 258) { record, _, store, plugin in
                let type = store.resolvedID(wanted.asFormID, fromPlugin: plugin)
                return Self.isTrue(type != nil && record?.associationType?.id == type)
            }
        })
        registry.register(ConditionFunction(
            index: 259, name: "HasFamilyRelationship", parameter1: .formID
        ) { call in
            relationshipRecord(call, index: 259) { record, _, _, _ in
                Self.isTrue(record?.associationType?.isFamilyAssociation == true)
            }
        })
        registry.register(ConditionFunction(
            index: 261, name: "HasParentRelationship", parameter1: .formID
        ) { call in
            relationshipRecord(call, index: 261) { record, base, _, _ in
                guard let record, record.associationType?.editorID == parentChildAssociation
                else { return 0 }
                return Self.isTrue(record.parent == base)
            }
        })
        registry.register(ConditionFunction(index: 616, name: "GetLowestRelationshipRank") { call in
            call.referenceKey().flatMap { actor in
                let seam = call.context.factions
                guard
                    let store = seam.derivation?.relationships,
                    let profile = seam.profile(of: actor)
                else { return .failure(.unavailableFactions) }
                let ranks = profile.base.map(store.relationships(involving:)) ?? []
                let lowest = ranks.compactMap { $0.rank?.signedRank }.min() ?? 0
                return .success(Float(lowest))
            }
        })
    }

    /// The `RELA` record between the run-on and parameter 1, nil when none names the
    /// pair. `read` also gets the run-on's base, the store, and the source plugin.
    private static func relationshipRecord(
        _ call: ConditionCall,
        index: UInt16,
        read: (ResolvedRelationship?, ResolvedFormID, RelationshipStore, String) -> Float
    ) -> Result<Float, ConditionFailure> {
        actorPair(call, index: index) { seam, actor, other in
            guard
                let store = seam.derivation?.relationships,
                let plugin = seam.facts.sourcePlugin,
                let base = seam.profile(of: actor)?.base,
                let otherBase = seam.profile(of: other)?.base
            else { return nil }
            return read(store.relationship(between: base, and: otherBase), base, store, plugin)
        }
    }
}
