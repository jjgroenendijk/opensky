// An actor's authored perk list (issue #497, roadmap item 20.4, scope point 1):
// the NPC_ `PRKR` run, and the template flag it inherits through.
//
// Records are synthetic and built in code — never extracted game files
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct ActorPerkBaselineTests {
    private enum Form {
        static let bandit: UInt32 = 0x0000_0100
        static let templateBandit: UInt32 = 0x0000_0101
        static let armsman: UInt32 = 0x0000_0300
        static let blocking: UInt32 = 0x0000_0301
    }

    /// `PRKR` decodes as its 8-byte struct: the link is read and the dead rank
    /// byte and its junk tail are not.
    @Test func thePerkRunIsDecodedInRecordOrder() throws {
        let npc = try ActorSpellFixture.npc(
            formID: Form.bandit, perks: [Form.armsman, Form.blocking]
        )

        #expect(npc.perks == [FormID(Form.armsman), FormID(Form.blocking)])
    }

    @Test func anActorWithNoPerkRunCarriesNone() throws {
        let npc = try ActorSpellFixture.npc(formID: Form.bandit)

        #expect(npc.perks.isEmpty)
    }

    @Test func theAuthoredListIsWhatTheBaselineResolves() throws {
        let resolver = try ActorSpellFixture.perkResolver(npcs: [
            ActorSpellFixture.npc(formID: Form.bandit, perks: [Form.armsman])
        ])

        #expect(resolver.baseline(for: FormID(Form.bandit)) == [FormID(Form.armsman)])
    }

    /// UESP names the ACBS bit "Use spelllist (both spells and perks)", so the
    /// perk list follows the template on exactly the flag the spell list does.
    @Test func thePerkListComesFromTheTemplateOnTheSpellListFlag() throws {
        let resolver = try ActorSpellFixture.perkResolver(npcs: [
            ActorSpellFixture.npc(
                formID: Form.bandit,
                templateFlags: 0x0008,
                template: Form.templateBandit
            ),
            ActorSpellFixture.npc(formID: Form.templateBandit, perks: [Form.armsman])
        ])

        #expect(resolver.baseline(for: FormID(Form.bandit)) == [FormID(Form.armsman)])
    }

    @Test func aLocalEmptyListStaysAuthoritativeWithoutTheFlag() throws {
        let resolver = try ActorSpellFixture.perkResolver(npcs: [
            ActorSpellFixture.npc(formID: Form.bandit, template: Form.templateBandit),
            ActorSpellFixture.npc(formID: Form.templateBandit, perks: [Form.armsman])
        ])

        #expect(resolver.baseline(for: FormID(Form.bandit)).isEmpty)
    }

    /// The player has no NPC_ record in this engine, which is what
    /// "seed the player empty" means.
    @Test func thePlayerHasNoAuthoredPerks() throws {
        let resolver = try ActorSpellFixture.perkResolver(npcs: [
            ActorSpellFixture.npc(formID: Form.bandit, perks: [Form.armsman])
        ])

        #expect(resolver.baseline(for: ActorValueSubject.player).isEmpty)
    }
}
