// The vanilla actor-value index table (issue #375, roadmap item 15.8).
//
// The table is data copied from xEdit's `wbActorValueEnum`, so the tests that
// matter are the ones that would catch a transcription slip: the three indices
// the engine actually resolves, the length, and the anchors on either side of
// each `Unknown NN` run — a dropped placeholder would renumber everything after
// it and no self-consistent test would notice.

import Foundation
@testable import opensky
import Testing

struct ActorValueIdentityTests {
    @Test func theStoredThreeSitAtTheirDocumentedIndices() {
        #expect(ActorValueIdentity.kind(at: 24) == .health)
        #expect(ActorValueIdentity.kind(at: 25) == .magicka)
        #expect(ActorValueIdentity.kind(at: 26) == .stamina)
        #expect(ActorValueIdentity.storedIndices == [
            .health: 24, .magicka: 25, .stamina: 26
        ])
    }

    @Test func tableLengthAndItsAnchorsMatchTheSource() {
        #expect(ActorValueIdentity.vanillaNames.count == 164)
        #expect(ActorValueIdentity.name(at: 0) == "Aggression")
        #expect(ActorValueIdentity.name(at: 163) == "Reflect Damage")
        // Either side of the 46...52 placeholder run.
        #expect(ActorValueIdentity.name(at: 45) == "Resist Disease")
        #expect(ActorValueIdentity.name(at: 46) == "Unknown 46")
        #expect(ActorValueIdentity.name(at: 53) == "Paralysis")
        // Either side of the lone 59 placeholder.
        #expect(ActorValueIdentity.name(at: 58) == "Water Walking")
        #expect(ActorValueIdentity.name(at: 60) == "Fame")
        // Either side of the lone 162 placeholder.
        #expect(ActorValueIdentity.name(at: 161) == "Grabbed")
        #expect(ActorValueIdentity.name(at: 162) == "Unknown 162")
    }

    /// The eighteen `Skill Advance` slots run in skill order from 114, which is
    /// what makes accumulated skill experience addressable by index (issue
    /// #498). A table edit that moved them would break the mapping silently,
    /// so both directions and every name are pinned here.
    @Test func everySkillJoinsItsOwnSkillAdvanceSlot() throws {
        #expect(
            ActorValueIdentity.name(at: ActorValueIdentity.firstSkillAdvanceIndex)
                == "One-Handed Skill Advance"
        )
        #expect(ActorValueIdentity.skillIndices.count == 18)

        for skill in ActorValueIdentity.skillIndices {
            let slot = try #require(ActorValueIdentity.skillAdvanceIndex(forSkill: skill))
            let name = try #require(ActorValueIdentity.name(at: slot))
            #expect(name.hasSuffix(" Skill Advance"))
            #expect(ActorValueIdentity.skillIndex(forAdvance: slot) == skill)
        }
        // Nothing outside the skills has a slot, and nothing outside the run of
        // slots names a skill.
        #expect(ActorValueIdentity.skillAdvanceIndex(forSkill: 24) == nil)
        #expect(
            ActorValueIdentity.skillIndex(
                forAdvance: ActorValueIdentity.firstSkillAdvanceIndex - 1
            ) == nil
        )
        #expect(
            ActorValueIdentity.skillIndex(
                forAdvance: ActorValueIdentity.firstSkillAdvanceIndex + 18
            ) == nil
        )
    }

    @Test func indicesOutsideTheTableNameNothing() {
        #expect(ActorValueIdentity.name(at: ActorValueIdentity.noneIndex) == nil)
        #expect(ActorValueIdentity.name(at: 164) == nil)
        #expect(ActorValueIdentity.kind(at: -1) == nil)
        #expect(ActorValueIdentity.kind(at: 164) == nil)
        #expect(ActorValueIdentity.description(of: 999) == "actor value 999")
        #expect(ActorValueIdentity.description(of: 24) == "Health")
    }

    @Test func namesMatchAcrossSpellingAndCase() {
        #expect(ActorValueIdentity.kind(named: "Health") == .health)
        #expect(ActorValueIdentity.kind(named: "health") == .health)
        // Whitespace is a non-alphanumeric like any other, so it normalizes
        // away rather than making a name unrecognizable.
        #expect(ActorValueIdentity.kind(named: " StAmInA ") == .stamina)
        // xEdit spells this one with a hyphen and Papyrus without; both land on
        // the same index, which is the whole point of the normalization.
        #expect(ActorValueIdentity.index(named: "One-Handed") == 6)
        #expect(ActorValueIdentity.index(named: "OneHanded") == 6)
        #expect(ActorValueIdentity.index(named: "Variable01") == 68)
    }

    @Test func realActorValuesTheEngineDoesNotStoreResolveToNoKind() {
        // A real, named actor value with no store behind it: the caller turns
        // this nil into its own tallied miss rather than a zero.
        #expect(ActorValueIdentity.index(named: "Sneak") == 15)
        #expect(ActorValueIdentity.kind(named: "Sneak") == nil)
        #expect(ActorValueIdentity.kind(at: 15) == nil)
        // A name no vanilla actor value carries at all.
        #expect(ActorValueIdentity.index(named: "Charisma") == nil)
        #expect(ActorValueIdentity.kind(named: "Charisma") == nil)
    }
}
