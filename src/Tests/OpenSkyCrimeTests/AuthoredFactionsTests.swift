// `doNotReportCrimesAgainstMembers` for an owner that `XOWN` names by its `NPC_`
// base: the check reads the base's authored `SNAM` list.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
@testable import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

@MainActor
struct AuthoredFactionsTests {
    private static let owner: UInt32 = 0x700

    @Test func aBaseOwnerInTheFactionIsAMember() throws {
        var runtime = try CrimeFixture.runtime()
        let tolerant = CrimeFixture.Factions.tolerant
        let event = CrimeFixture.event(.trespass, faction: tolerant, victim: Self.owner)
        #expect(runtime.report(event).refusal == nil)

        runtime.authoredFactions = try Self.authored(factions: [(tolerant, 0)])
        let outcome = runtime.report(event)
        #expect(outcome.gold == 0)
        #expect(outcome.refusal == .victimIsMember)
    }

    @Test func aKeyThatIsNoRecordHasNoFactions() throws {
        let runtime = try CrimeFixture.runtime()
        let authored = try Self.authored(factions: [(CrimeFixture.Factions.tolerant, 0)])
        #expect(authored.memberships(ofBase: .player, factions: runtime.factions).isEmpty)
    }

    private static func authored(factions: [(UInt32, Int8)]) throws -> AuthoredFactions {
        let base = try FactionFixture.actorBase(
            formID: owner, editorID: "Owner", factions: factions.map { ($0.0, $0.1) }
        )
        return AuthoredFactions(
            baselines: ActorFactionBaselineResolver(templates: ActorTemplateResolver(
                actors: [base.formID.rawValue: base], leveledActors: [:]
            )),
            pluginName: CrimeFixture.pluginName
        )
    }
}
