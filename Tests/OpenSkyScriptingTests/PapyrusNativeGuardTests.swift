// The guard and arrest natives (issue #505): `Actor.GetCrimeFaction`,
// `Actor.IsGuard`, `Faction.CanPayCrimeGold`, `Faction.PlayerPayCrimeGold`
// and `Faction.SendPlayerToJail`, over a stand-in session that runs the real
// `CrimeArrest` against the fixture store.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import FormatsESMTesting
import Foundation
@testable import OpenSkyCrime
@testable import OpenSkyCrimeInterface
@testable import OpenSkyCrimeTesting
@testable import OpenSkyFactions
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import OpenSkyInventoryTesting
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyScriptingTesting
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeGuardTests {
    private typealias Items = InventoryBaselineFixture

    private let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

    /// The session half of an arrest with no clock or placement to move: the
    /// engine outcome and a record of what was asked.
    private final class ArrestSession: CrimeArrestSession {
        let arrest: CrimeArrest
        private(set) var outcomes: [ArrestOutcome] = []

        init(arrest: CrimeArrest) {
            self.arrest = arrest
        }

        func canPayCrimeGold(to faction: ReferenceKey) -> Bool? {
            arrest.canPay(faction)
        }

        func settleArrest(
            with faction: ReferenceKey,
            _ outcome: ArrestOutcome
        ) -> Result<ArrestSettlement, ArrestRefusal>? {
            outcomes.append(outcome)
            let evidence = arrest.unresidentEvidence(of: faction)
            return switch outcome {
            case let .pay(removeStolen, goToJail):
                Result { () throws(ArrestRefusal) in
                    try arrest.pay(
                        faction, removeStolen: removeStolen, goToJail: goToJail,
                        evidence: evidence
                    )
                }
            case .jail:
                Result { () throws(ArrestRefusal) in
                    try arrest.jail(faction, evidence: evidence)
                }
            }
        }
    }

    private struct Fixture {
        // Held so the world and bridge the registry reaches
        // stay alive for the length of a test
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let actor: PapyrusObjectHandle
        let faction: PapyrusObjectHandle
        let crime: CrimeRuntime
        let inventory: InventoryRuntime
        let arrests: ArrestSession
    }

    private func fixture(
        guardMember: Bool = true,
        crimeFaction: UInt32? = CrimeFixture.Factions.hold,
        wired: Bool = true
    ) throws -> Fixture {
        let entry = try PapyrusWorldFixture.actorEntry(
            objectID: 0x0004_0001,
            base: 0x0004_0002,
            scripts: [VMADFixture.Script("Resident", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Resident", events: [])],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        let store = try CrimeFixture.factionStore()
        let crime = CrimeRuntime(store: session.worldState, factions: store)
        let inventory = try InventoryRuntime(
            store: session.worldState, baselines: Items.resolver()
        )
        let arrests = ArrestSession(arrest: CrimeArrest(crime: crime, inventory: inventory))
        if wired {
            let factions = try FactionRuntime(
                store: session.worldState,
                factions: store,
                derivation: HostilityDerivation(
                    relations: FactionRelationIndex(store: store),
                    relationships: RelationshipStore(
                        plugins: [(CrimeFixture.pluginName, CrimeFixture.file())]
                    )
                )
            )
            let memberships = guardMember ? [(CrimeFixture.Factions.guards, Int8(0))] : []
            session.bridge.factionRuntime = { _ in factions }
            session.bridge.socialProfile = { key in
                ActorSocialProfile(
                    key: key,
                    memberships: CrimeFixture.state(memberships),
                    crimeFaction: crimeFaction.map(CrimeFixture.key)
                )
            }
            session.bridge.arrestSession = { arrests }
        }
        return try Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            actor: #require(session.bridge.objectHandle(for: entry.key)),
            faction: #require(session.bridge.objectHandle(for: hold)),
            crime: crime,
            inventory: inventory,
            arrests: arrests
        )
    }

    /// One method call on `receiver`, through the fixture's registry.
    @discardableResult
    private func call(
        _ scriptName: String,
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        let request = PapyrusWorldFixture.methodCall(
            scriptName, functionName,
            receiver: receiver, arguments: arguments, returnType: returnType
        )
        return fixture.registry.invoke(request)
    }

    /// Whether the native refused rather than answering.
    private func isFailure(_ result: PapyrusNativeResult) -> Bool {
        guard case .failed = result else { return false }
        return true
    }

    // MARK: - Actor

    @Test func getCrimeFactionAnswersTheFactionHandleOrNone() throws {
        let reporting = try fixture()
        #expect(call(
            "Actor", "GetCrimeFaction", reporting, receiver: reporting.actor,
            returnType: .object("Faction")
        ) == .returned(.object(reporting.faction)))

        let silent = try fixture(crimeFaction: nil)
        #expect(call(
            "Actor", "GetCrimeFaction", silent, receiver: silent.actor,
            returnType: .object("Faction")
        ) == .returned(.none))
    }

    @Test func isGuardNeedsTheGuardFactionAndACrimeFaction() throws {
        let guardian = try fixture()
        #expect(call("Actor", "IsGuard", guardian, receiver: guardian.actor, returnType: .boolean)
            == .returned(.boolean(true)))
        let civilian = try fixture(guardMember: false)
        #expect(call("Actor", "IsGuard", civilian, receiver: civilian.actor, returnType: .boolean)
            == .returned(.boolean(false)))
    }

    @Test func aSessionWithNoDataRefusesRatherThanAnswering() throws {
        let bare = try fixture(wired: false)
        #expect(isFailure(call("Actor", "IsGuard", bare, receiver: bare.actor)))
        #expect(isFailure(call("Actor", "GetCrimeFaction", bare, receiver: bare.actor)))
        #expect(isFailure(call("Faction", "CanPayCrimeGold", bare, receiver: bare.faction)))
        #expect(isFailure(call("Faction", "SendPlayerToJail", bare, receiver: bare.faction)))
    }

    // MARK: - Faction

    @Test func playerPayCrimeGoldDefaultsToSeizingAndGoingToJail() throws {
        let fixture = try fixture()
        fixture.crime.setCrimeGold(40, of: hold)
        try fixture.inventory.add(Items.gold, count: 50, to: .player)
        #expect(call(
            "Faction", "CanPayCrimeGold", fixture, receiver: fixture.faction, returnType: .boolean
        ) == .returned(.boolean(true)))

        #expect(call("Faction", "PlayerPayCrimeGold", fixture, receiver: fixture.faction)
            == .returned(.none))
        #expect(fixture.arrests.outcomes == [.pay(removeStolen: true, goToJail: true)])
        #expect(fixture.crime.crimeGold(of: hold) == 0)
        #expect(fixture.inventory.goldCount(of: .player) == 10)
    }

    @Test func playerPayCrimeGoldPassesItsFlagsAndRefusesWhenPoor() throws {
        let fixture = try fixture()
        fixture.crime.setCrimeGold(40, of: hold)
        #expect(isFailure(call(
            "Faction", "PlayerPayCrimeGold", fixture,
            receiver: fixture.faction, arguments: [.boolean(false), .boolean(false)]
        )))
        #expect(fixture.arrests.outcomes == [.pay(removeStolen: false, goToJail: false)])
        #expect(fixture.crime.crimeGold(of: hold) == 40)
    }

    @Test func sendPlayerToJailServesTheSentence() throws {
        let fixture = try fixture()
        fixture.crime.setCrimeGold(300, of: hold)
        #expect(call("Faction", "SendPlayerToJail", fixture, receiver: fixture.faction)
            == .returned(.none))
        #expect(fixture.arrests.outcomes == [.jail])
        #expect(fixture.crime.crimeGold(of: hold) == 0)
        #expect(isFailure(call("Faction", "SendPlayerToJail", fixture, receiver: fixture.faction)))
    }
}
