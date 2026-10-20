// Guard response: who is a guard, which bounty means talk or fight, the crime
// term of hostility, and one confrontation at a time.

import Foundation
@testable import OpenSkyCrime
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactions
import OpenSkyFactionsFixtures
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct GuardResponseTests {
    private let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private let guardFaction = CrimeFixture.key(CrimeFixture.Factions.guards)

    /// A `CRVA` decoded from fixture bytes, so the flags go through the real
    /// decoder rather than a memberwise initializer.
    private func values(arrest: Bool, attackOnSight: Bool) throws -> Faction.CrimeValues {
        let bytes = CrimeFixture.faction(
            0x40, "Probe",
            flags: CrimeFixture.Flags.tracksCrime,
            crimeValues: FactionFixture.crimeValues(arrest: arrest, attackOnSight: attackOnSight)
        )
        let faction = try Faction(record: FactionFixture.decode(bytes), localized: false)
        return try #require(faction.crimeValues)
    }

    private func guardProfile(
        _ reference: UInt32 = 0x800,
        member: Bool = true,
        crimeFaction: UInt32? = CrimeFixture.Factions.hold
    ) -> ActorSocialProfile {
        ActorSocialProfile(
            key: CrimeFixture.key(reference),
            memberships: CrimeFixture.state(
                member ? [(CrimeFixture.Factions.guards, Int8(0))] : []
            ),
            crimeFaction: crimeFaction.map(CrimeFixture.key)
        )
    }

    // MARK: - Recognition

    @Test func theGuardFactionComesFromTheDefaultObject() throws {
        let store = try CrimeFixture.factionStore()
        #expect(store.guardFactionKey == guardFaction)
        #expect(store.guardFaction?.editorID == "GuardFaction")
    }

    @Test func aGuardIsAMemberOfTheGuardFactionThatReportsSomewhere() {
        #expect(
            GuardRecognition.policedFaction(of: guardProfile(), guardFaction: guardFaction)
                == hold
        )
        #expect(
            GuardRecognition.policedFaction(
                of: guardProfile(member: false), guardFaction: guardFaction
            ) == nil
        )
        #expect(
            GuardRecognition.policedFaction(
                of: guardProfile(crimeFaction: nil), guardFaction: guardFaction
            ) == nil
        )
        #expect(GuardRecognition.policedFaction(of: guardProfile(), guardFaction: nil) == nil)
    }

    private func row(_ nonViolent: Int32, violent: Int32 = 0) -> CrimeLedgerEntry {
        CrimeLedgerEntry(faction: hold, nonViolentGold: nonViolent, violentGold: violent)
    }

    /// The line past which the vanilla settings fight: `iAttackOnSightViolent`.
    private let line = CrimeSettings.vanilla.attackOnSightViolent

    // MARK: - Policy

    @Test func arrestFactionsConfrontAndAttackOnSightFactionsFightPastTheLine() throws {
        let arresting = try values(arrest: true, attackOnSight: false)
        let attacking = try values(arrest: true, attackOnSight: true)
        let lenient = try values(arrest: false, attackOnSight: false)

        #expect(line == 2999)
        #expect(CrimeResponsePolicy.response(row(0), values: arresting) == .none)
        #expect(CrimeResponsePolicy.response(nil, values: arresting) == .none)
        #expect(CrimeResponsePolicy.response(row(40), values: nil) == .none)
        // Without Arrest, any bounty is fought.
        #expect(CrimeResponsePolicy
            .response(row(40), values: lenient) == .attackOnSight(bounty: 40))
        #expect(CrimeResponsePolicy.response(row(0, violent: line + 1), values: arresting)
            == .confront(bounty: line + 1))
        #expect(CrimeResponsePolicy.response(row(0, violent: line), values: attacking)
            == .confront(bounty: line))
        #expect(CrimeResponsePolicy.response(row(0, violent: line + 1), values: attacking)
            == .attackOnSight(bounty: line + 1))
        // Non-violent gold never fights at the vanilla 0, however high.
        #expect(CrimeResponsePolicy.response(row(50000), values: attacking)
            == .confront(bounty: 50000))
        var strict = CrimeSettings.vanilla
        strict.attackOnSightNonViolent = 500
        #expect(CrimeResponsePolicy.response(row(501), values: attacking, settings: strict)
            == .attackOnSight(bounty: 501))
    }

    // MARK: - Hostility

    @Test func guardsTurnHostileOnlyPastTheLineOrAfterResistance() throws {
        let player = ActorSocialProfile(key: .player)
        let attacking = try values(arrest: true, attackOnSight: true)
        func hostility(
            bounty: Int32, violent: Int32 = 0, resisted: Set<ReferenceKey> = []
        ) -> ActorReaction? {
            GuardCrimeHostility(
                guardFaction: guardFaction,
                bounties: [hold: row(bounty, violent: violent)],
                crimeValues: [hold: attacking],
                resisted: resisted
            ).crimeReaction(of: guardProfile(), toward: player)
        }

        #expect(hostility(bounty: 40) == nil)
        #expect(hostility(bounty: 40, resisted: [hold]) == .enemy)
        #expect(hostility(bounty: 0, violent: line + 1) == .enemy)
        #expect(hostility(bounty: 0, violent: line) == nil)
        #expect(hostility(bounty: 0, resisted: [hold]) == nil)
    }

    @Test func nonGuardsAndOtherTargetsGetNoOpinionFromCrime() throws {
        let term = try GuardCrimeHostility(
            guardFaction: guardFaction,
            bounties: [hold: row(5000)],
            crimeValues: [hold: values(arrest: true, attackOnSight: true)],
            resisted: [hold]
        )
        let civilian = guardProfile(member: false)
        #expect(term.crimeReaction(of: civilian, toward: ActorSocialProfile(key: .player)) == nil)
        #expect(term.crimeReaction(of: guardProfile(), toward: civilian) == nil)
    }

    @Test func theDerivationPutsTheCrimeTermAboveTheFactionTerms() throws {
        var derivation = try HostilityFixture.derivation()
        derivation.crime = try GuardCrimeHostility(
            guardFaction: guardFaction,
            bounties: [hold: row(40)],
            crimeValues: [hold: values(arrest: true, attackOnSight: false)],
            resisted: [hold]
        )
        let decision = derivation.decide(guardProfile(), toward: ActorSocialProfile(key: .player))
        #expect(decision.reaction == .enemy)
        #expect(decision.source == .crime)
    }

    // MARK: - Confrontation

    private func candidate(
        _ reference: UInt32,
        distance: Float,
        detects: Bool = true
    ) -> GuardCandidate {
        GuardCandidate(
            guardKey: CrimeFixture.key(reference),
            crimeFaction: hold,
            detectsPlayer: detects,
            distance: distance
        )
    }

    private func actions(
        _ state: GuardResponseState,
        _ guards: [GuardCandidate],
        bounty: Int32 = 40,
        violent: Int32 = 0,
        attackOnSight: Bool = false,
        now: Double = 0
    ) throws -> [GuardAction] {
        let crva = try values(arrest: true, attackOnSight: attackOnSight)
        let entry = row(bounty, violent: violent)
        return state.actions(
            guards: guards,
            bounty: { _ in entry },
            values: { _ in crva },
            now: now
        )
    }

    @Test func theNearestDetectingGuardPursuesThenConfronts() throws {
        let state = GuardResponseState()
        let far = GuardResponseState.confrontDistance * 4
        let pursuing = try actions(state, [
            candidate(0x801, distance: far),
            candidate(0x802, distance: far * 2),
            candidate(0x803, distance: 1, detects: false)
        ])
        #expect(pursuing == [.pursue(guardKey: CrimeFixture.key(0x801), crimeFaction: hold)])

        let confronting = try actions(state, [candidate(0x801, distance: 10)])
        #expect(confronting == [.confront(
            guardKey: CrimeFixture.key(0x801), crimeFaction: hold, bounty: 40
        )])
    }

    @Test func noBountyOrAnAttackOnSightBountyStartsNoConversation() throws {
        let state = GuardResponseState()
        #expect(try actions(state, [candidate(0x801, distance: 10)], bounty: 0).isEmpty)
        #expect(try actions(
            state, [candidate(0x801, distance: 10)],
            bounty: 0, violent: line + 1, attackOnSight: true
        ).isEmpty)
    }

    @Test func oneConversationAtATimeAndACooldownAfterOneThatCouldNotRun() throws {
        var state = GuardResponseState()
        let near = [candidate(0x801, distance: 10)]
        let open = try #require(try actions(state, near).first)
        state.begin(open)
        #expect(try actions(state, near).isEmpty)

        state.end(settled: false, now: 100)
        #expect(try actions(state, near, now: 100).isEmpty)
        let later = 100 + GuardResponseState.reconfrontGameSeconds
        #expect(try actions(state, near, now: later) == [open])
    }

    @Test func resistingSilencesTheFactionUntilItIsForgiven() throws {
        var state = GuardResponseState()
        let near = [candidate(0x801, distance: 10)]
        try state.begin(#require(try actions(state, near).first))
        state.resist(hold, now: 0)
        #expect(state.active == nil)
        #expect(state.resisted == [hold])
        #expect(try actions(state, near).isEmpty)

        state.forgive(hold)
        #expect(try actions(state, near).count == 1)
        state.resist(hold, now: 0)
        state.reset()
        #expect(state == GuardResponseState())
    }
}
