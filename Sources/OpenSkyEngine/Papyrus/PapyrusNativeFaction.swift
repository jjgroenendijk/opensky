// The faction and relationship natives (issue #508, roadmap item 21.4): the
// `Actor` membership family, the two relationship accessors, the two pair
// questions, and the one `Faction` reaction read — over 21.3's faction runtime
// and this item's relationship runtime.
//
// `PapyrusNativeActor.swift` recorded the absence this file ends: "SetRelationshipRank
// and the faction natives are absent with the factions themselves". They are not
// any more.
//
// Policy is the `Actor`, perk and crime families', unchanged: `self` arrives as
// `PapyrusNativeCall.receiver` and becomes a `ReferenceKey`; a headless runtime,
// a handle with no world identity, or a session with no faction data is a
// failure with a reason rather than a guess, and the interpreter substitutes the
// call's declared default so the script keeps running.
//
// Every signature below is quoted from the Creation Kit wiki at the registration
// site rather than recalled, because a Papyrus signature is an interface a mod's
// compiled bytecode already agrees with: a wrong argument count is a script that
// stops working, not a number that reads slightly off.
// `PapyrusNativeSignatureRealDataTests` checks each one against the declaration
// in the install's own `Actor.pex` and `Faction.pex`, which is the only source
// that cannot have drifted from the game.
//
// ## `AddToFaction` is not native, and is registered anyway
//
// The install's own `Actor.pex` declares `AddToFaction` as an ordinary Papyrus
// wrapper rather than a native, and its whole compiled body is
// `if !IsInFaction(akFaction); SetFactionRank(akFaction, 0); endIf` — read off
// the bytecode by `PapyrusNativeSignatureRealDataTests`, which is also where the
// "does nothing when already a member" rule below comes from. Registering it is
// therefore not an invention: it is that body, and it means the call works
// whether or not this session could load the game's own script.
//
// ## What is deliberately absent, and why
//
// * `Faction.SetReaction` and `Faction.ModReaction`. Both write the interfaction
//   `XNAM` table, and `FactionRelationIndex` is a derived read-only index built
//   once from the records. Backing them needs a runtime relation override this
//   item does not build, and a writer that silently did nothing would be worse
//   than a counted gap. `Faction.GetReaction` is registered, because reading is
//   already backed.
// * `Actor.ModFactionRank`. It reads the current rank, adds a delta and writes
//   the result — arithmetic over `SetFactionRank`, whose semantics for a
//   non-member the Creation Kit wiki does not state on any reachable mirror, and
//   the sweep can report the shipped signature but not what the number means.
//   Guessing whether a delta joins an outsider at the delta or at zero would put
//   a wrong rank in the save, so it stays counted.
// * The `Faction` crime-gold family, which is #504's and already registered in
//   `PapyrusNativeCrime.swift`.
//
// An unimplemented native is counted by name in `PapyrusNativeLog`, which is
// what ranks the next one to build.
//
// Documented in docs/engine/papyrus-actor-natives.md and docs/engine/hostility.md.

import Foundation
import OpenSkyFormats

nonisolated extension PapyrusNativeFunctions {
    static func installFaction(into registry: inout PapyrusNativeRegistry) {
        installFactionMemberships(into: &registry)
        installFactionRanks(into: &registry)
        installRelationshipRanks(into: &registry)
        installSocialReads(into: &registry)
    }

    /// Joining and leaving.
    private static func installFactionMemberships(
        into registry: inout PapyrusNativeRegistry
    ) {
        // "Adds the Actor to a specified faction at rank 0." —
        // `Function AddToFaction(Faction akFaction)`
        // (<https://ck.uesp.net/wiki/AddToFaction_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "AddToFaction"
        ) { call, context in
            memberFactionTarget(call, context) { actor, faction in
                guard actor.world.addToFaction(actor.key, faction: faction) != nil else {
                    return needsFactionRuntime(call)
                }
                return .returned(.none)
            }
        })

        // "Removes this actor from the specified faction." —
        // `Function RemoveFromFaction(Faction akFaction) native`
        // (<https://ck.uesp.net/wiki/RemoveFromFaction_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "RemoveFromFaction"
        ) { call, context in
            memberFactionTarget(call, context) { actor, faction in
                guard actor.world.removeFromFaction(actor.key, faction: faction) != nil else {
                    return needsFactionRuntime(call)
                }
                return .returned(.none)
            }
        })
    }

    /// Reading and writing a rank.
    private static func installFactionRanks(
        into registry: inout PapyrusNativeRegistry
    ) {
        // "Returns whether this actor is a member of the specified faction or
        // not." — `bool Function IsInFaction(Faction akFaction) native`
        // (<https://ck.uesp.net/wiki/IsInFaction_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "IsInFaction"
        ) { call, context in
            memberFactionTarget(call, context) { actor, faction in
                guard let member = actor.world.isInFaction(actor.key, faction: faction) else {
                    return needsFactionRuntime(call)
                }
                return .returned(.boolean(member))
            }
        })

        // "Gets this actor's rank in the specified faction ... -2 if the Actor is
        // not in the faction. -1 if the Actor is in the faction, with a rank set
        // to -1." — `int Function GetFactionRank(Faction akFaction) native`
        // (<https://ck.uesp.net/wiki/GetFactionRank_-_Actor>)
        //
        // The -2 is applied here rather than in the seam, so the condition
        // function of the same name can keep answering the -1 *its* page
        // documents from the same stored rank.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "GetFactionRank"
        ) { call, context in
            memberFactionTarget(call, context) { actor, faction in
                guard let rank = actor.world.factionRank(of: actor.key, in: faction) else {
                    return needsFactionRuntime(call)
                }
                return .returned(.integer(rank.map(Int32.init) ?? -2))
            }
        })

        // "Sets this actor's rank in the specified faction. Adds the actor to the
        // faction if necessary." —
        // `Function SetFactionRank(Faction akFaction, int aiRank) native`
        // (<https://ck.uesp.net/wiki/SetFactionRank_-_Actor>). The page gives the
        // "valid range is -128 to 127", which is the `SNAM` rank byte, so a value
        // outside it is a refusal rather than a wrap.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "SetFactionRank"
        ) { call, context in
            memberFactionTarget(call, context) { actor, faction in
                guard
                    let raw = integer(call, at: 1),
                    let rank = Int8(exactly: raw)
                else {
                    return failure(call, "SetFactionRank needs a rank in -128...127")
                }
                guard
                    actor.world.setFactionRank(rank, of: actor.key, in: faction) != nil
                else {
                    return needsFactionRuntime(call)
                }
                return .returned(.none)
            }
        })
    }

    /// The two `Actor` relationship accessors.
    private static func installRelationshipRanks(
        into registry: inout PapyrusNativeRegistry
    ) {
        // "Gets the relationship rank between this actor and another ... 4: Lover
        // ... -4: Archnemesis" —
        // `int Function GetRelationshipRank(Actor akOther) native`
        // (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>)
        //
        // A pair nothing names is a refusal rather than 0, because 0 is
        // Acquaintance and a script comparing `>= 1` would read an unknown pair
        // as a deliberate indifference the records never authored.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "GetRelationshipRank"
        ) { call, context in
            actorPair(call, context) { actor, other in
                guard
                    let stored = actor.world.relationshipRank(of: actor.key, toward: other),
                    let rank = stored
                else {
                    return failure(
                        call,
                        "GetRelationshipRank knows no relationship between those actors"
                    )
                }
                return .returned(.integer(Int32(rank)))
            }
        })

        // "Sets the relationship rank between this actor and another." —
        // `Function SetRelationshipRank(Actor akOther, int aiRank) native`
        // (<https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor>). The page
        // lists -4...4 as "acceptable"; a value outside it is refused rather than
        // stored, because the rank is read back through a table that names only
        // those nine.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "SetRelationshipRank"
        ) { call, context in
            actorPair(call, context) { actor, other in
                guard
                    let raw = integer(call, at: 1),
                    RelationshipRank(signedRank: Int(raw)) != nil
                else {
                    return failure(call, "SetRelationshipRank needs a rank in -4...4")
                }
                guard
                    actor.world.setRelationshipRank(
                        Int8(clamping: raw), of: actor.key, toward: other
                    ) != nil
                else {
                    return failure(
                        call,
                        "SetRelationshipRank needs a session with a relationship runtime"
                    )
                }
                return .returned(.none)
            }
        })
    }

    /// The two pair reads: what two actors' factions make of each other, and what
    /// two factions make of each other.
    private static func installSocialReads(into registry: inout PapyrusNativeRegistry) {
        // "Get the faction-based reaction between this actor and another ... 0:
        // Neutral, 1: Enemy, 2: Ally, 3: Friend" —
        // `int Function GetFactionReaction(Actor akOther) native`
        // (<https://ck.uesp.net/wiki/GetFactionReaction_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "GetFactionReaction"
        ) { call, context in
            actorPair(call, context) { actor, other in
                guard
                    let reaction = actor.world.factionReaction(of: actor.key, toward: other)
                else {
                    return needsFactionRuntime(call)
                }
                return .returned(.integer(Int32(reaction)))
            }
        })

        // `bool Function IsHostileToActor(Actor akActor) native`, read off the
        // install's own compiled `Actor.pex` by
        // `PapyrusNativeSignatureRealDataTests`. The Creation Kit wiki carries no
        // page for it on any mirror reachable from here, and neither does its
        // condition-function twin at xEdit index 719, so the shipped declaration
        // is the whole source for the signature. The semantics are this engine's
        // hostility precedence list asked about the pair — the same answer the
        // combat loop acts on, rather than a second one written here.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "IsHostileToActor"
        ) { call, context in
            actorPair(call, context) { actor, other in
                guard let hostile = actor.world.isHostile(actor.key, toward: other) else {
                    return needsFactionRuntime(call)
                }
                return .returned(.boolean(hostile))
            }
        })

        // "Int GetReaction(Faction akOther): Gets this faction's reaction towards
        // the other faction." (<https://ck.uesp.net/wiki/Faction_Script>)
        //
        // A `Faction` script's `self` is a form rather than a placed reference,
        // and this engine addresses a FACT by the same `ReferenceKey` its
        // memberships are keyed by — so the receiver resolves exactly as an
        // `Actor` receiver does, which is the same reasoning
        // `PapyrusNativeCrime.factionTarget` states.
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "GetReaction"
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return failure(
                    call,
                    "GetReaction needs a world runtime and a faction receiver"
                )
            }
            guard
                let handle = objectArgument(call, at: 0),
                let other = target.world.referenceKey(for: handle)
            else {
                return failure(call, "GetReaction needs a faction argument")
            }
            guard
                let reaction = target.world.factionRelation(of: target.key, toward: other)
            else {
                return needsFactionRuntime(call)
            }
            return .returned(.integer(Int32(reaction)))
        })
    }

    // MARK: - Shared

    /// An `Actor` faction native: resolve the receiver and the FACT argument,
    /// then run `body`.
    private static func memberFactionTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: ((world: PapyrusWorldAccess, key: ReferenceKey), ReferenceKey)
            -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let actor = actorTarget(call, context) else {
            return needsActor(call)
        }
        guard
            let handle = objectArgument(call, at: 0),
            let faction = actor.world.referenceKey(for: handle)
        else {
            return failure(call, "\(call.functionName) needs a faction argument")
        }
        return body(actor, faction)
    }

    /// An `Actor` native about a second actor: resolve the receiver and the
    /// `Actor` argument, then run `body`.
    private static func actorPair(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: ((world: PapyrusWorldAccess, key: ReferenceKey), ReferenceKey)
            -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let actor = actorTarget(call, context) else {
            return needsActor(call)
        }
        guard
            let handle = objectArgument(call, at: 0),
            let other = actor.world.referenceKey(for: handle)
        else {
            return failure(call, "\(call.functionName) needs an actor argument")
        }
        return body(actor, other)
    }

    /// The single failure every faction native returns for a session that runs
    /// no faction runtime.
    private static func needsFactionRuntime(
        _ call: PapyrusNativeCall
    ) -> PapyrusNativeResult {
        failure(call, "\(call.functionName) needs a session with a faction runtime")
    }
}
