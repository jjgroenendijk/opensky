// The crime natives (issue #504, roadmap item 21.5): the `Faction` crime-gold
// trio and the two `Actor` alarms over a live crime runtime, plus the refusal a
// script has to be able to tell apart from a zero bounty.
//
// The bridge closure is the session's — every mutation goes through
// `CrimeRuntime` and lands in the world-state store, so a scripted bounty is
// saved exactly like a witnessed one.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeCrimeTests {
    /// A scripted actor plus a crime reporter wired into the bridge the way
    /// `GameViewControllerPapyrus` wires the session's.
    private struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let actor: PapyrusObjectHandle
        let actorKey: ReferenceKey
        let reporter: CrimeReporter
        let world: FakeCrimeWorld
    }

    /// The session facts a crime needs, answered by hand: the witness stands in
    /// a cell the hold answers for, and nothing is owned.
    private final class FakeCrimeWorld: CrimeWorld {
        var cell: CellSceneLocation? = .interior(FormID(0x50))
        var faction: ReferenceKey? = CrimeFixture.key(CrimeFixture.Factions.hold)

        func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
            nil
        }

        func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
            faction
        }

        func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
            cell
        }

        func crimeItemValue(of item: FormID) -> Int64 {
            0
        }

        func crimeActor(_ key: ReferenceKey) -> CrimeActor {
            CrimeActor(key: key)
        }
    }

    private static func fixture(wireReporter: Bool = true) throws -> Fixture {
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
        let world = FakeCrimeWorld()
        let reporter = try CrimeReporter(
            runtime: CrimeRuntime(
                store: session.worldState, factions: CrimeFixture.factionStore()
            ),
            world: world
        )
        if wireReporter {
            session.bridge.crimeReporter = { reporter }
        }
        return try Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            actor: #require(session.bridge.objectHandle(for: entry.key)),
            actorKey: entry.key,
            reporter: reporter,
            world: world
        )
    }

    @discardableResult
    private func call(
        _ scriptName: String,
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            scriptName,
            functionName,
            receiver: receiver,
            arguments: arguments,
            returnType: returnType
        ))
    }

    /// Whether the native refused, for the suites that only care that it did.
    private func isFailure(_ result: PapyrusNativeResult) -> Bool {
        if case .failed = result {
            return true
        }
        return false
    }

    /// The FACT's own handle, which is what a `Faction` script's `self` is.
    private func factionHandle(_ fixture: Fixture) throws -> PapyrusObjectHandle {
        try #require(
            fixture.session.bridge.objectHandle(
                for: CrimeFixture.key(CrimeFixture.Factions.hold)
            )
        )
    }

    // MARK: - Faction crime gold

    /// `int GetCrimeGold()`, `ModCrimeGold(int, bool)` and `SetCrimeGold(int)`
    /// over one ledger, in the order a fine is charged and then paid.
    @Test func theFactionCrimeGoldTrioReadsAndWritesOneLedger() throws {
        let fixture = try Self.fixture()
        let faction = try factionHandle(fixture)
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

        #expect(call(
            "Faction", "GetCrimeGold", fixture, receiver: faction, returnType: .integer
        ) == .returned(.integer(0)))

        call("Faction", "ModCrimeGold", fixture, receiver: faction, arguments: [.integer(40)])
        #expect(fixture.reporter.runtime.crimeGold(of: hold) == 40)
        #expect(call(
            "Faction", "GetCrimeGold", fixture, receiver: faction, returnType: .integer
        ) == .returned(.integer(40)))

        // The declared `abViolent` flag is accepted and ignored: one total.
        call(
            "Faction", "ModCrimeGold", fixture,
            receiver: faction, arguments: [.integer(-10), .boolean(true)]
        )
        #expect(fixture.reporter.runtime.crimeGold(of: hold) == 30)

        call("Faction", "SetCrimeGold", fixture, receiver: faction, arguments: [.integer(0)])
        #expect(fixture.reporter.runtime.crimeGold(of: hold) == 0)
    }

    /// Paying a bounty off settles the debt and leaves the crime counts alone.
    @Test func settingCrimeGoldLeavesTheCountsAlone() throws {
        let fixture = try Self.fixture()
        let faction = try factionHandle(fixture)
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
        fixture.reporter.runtime.report(CrimeFixture.event(.murder))

        call("Faction", "SetCrimeGold", fixture, receiver: faction, arguments: [.integer(0)])

        #expect(fixture.reporter.runtime.crimeGold(of: hold) == 0)
        #expect(fixture.reporter.runtime.crimeCounts(of: hold).murder == 1)
    }

    /// An amount that is not an integer is a refusal rather than a silent zero.
    @Test func aMissingAmountIsRefused() throws {
        let fixture = try Self.fixture()
        let faction = try factionHandle(fixture)

        #expect(isFailure(call("Faction", "ModCrimeGold", fixture, receiver: faction)))
        #expect(isFailure(call("Faction", "SetCrimeGold", fixture, receiver: faction)))
    }

    /// A session with no crime runtime refuses rather than reporting that the
    /// player owes nothing.
    @Test func aSessionWithNoCrimeRuntimeRefuses() throws {
        let fixture = try Self.fixture(wireReporter: false)
        let faction = try factionHandle(fixture)

        #expect(isFailure(call(
            "Faction", "GetCrimeGold", fixture, receiver: faction, returnType: .integer
        )))
        #expect(isFailure(call(
            "Actor", "SendAssaultAlarm", fixture, receiver: fixture.actor
        )))
    }

    // MARK: - The alarms

    /// `SendAssaultAlarm()` takes no arguments and charges the assault price
    /// with the crime faction of the place the witness stands in.
    @Test func theAssaultAlarmChargesTheAssaultPrice() throws {
        let fixture = try Self.fixture()

        call("Actor", "SendAssaultAlarm", fixture, receiver: fixture.actor)

        #expect(
            fixture.reporter.runtime
                .crimeGold(of: CrimeFixture.key(CrimeFixture.Factions.hold)) == 40
        )
    }

    /// `SendTrespassAlarm(Actor akCriminal)` names its criminal, and the alarm
    /// is credited as witnessed outright — the script is asserting that this
    /// actor caught them.
    @Test func theTrespassAlarmNamesItsCriminalAndIsAlwaysWitnessed() throws {
        let fixture = try Self.fixture()
        let player = try #require(fixture.session.bridge.objectHandle(for: .player))
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

        call(
            "Actor", "SendTrespassAlarm", fixture,
            receiver: fixture.actor, arguments: [.object(player)]
        )

        #expect(fixture.reporter.runtime.crimeGold(of: hold) == 5)
        #expect(fixture.reporter.runtime.crimeCounts(of: hold).trespass == 1)
    }

    /// A trespass alarm with no criminal argument is refused rather than
    /// charged to nobody.
    @Test func theTrespassAlarmNeedsACriminal() throws {
        let fixture = try Self.fixture()

        #expect(isFailure(call(
            "Actor", "SendTrespassAlarm", fixture, receiver: fixture.actor
        )))
    }

    /// An alarm raised where no crime faction answers charges nothing, which is
    /// the wilderness case rather than an error.
    @Test func anAlarmOutsideAnyHoldChargesNothing() throws {
        let fixture = try Self.fixture()
        fixture.world.faction = nil

        call("Actor", "SendAssaultAlarm", fixture, receiver: fixture.actor)

        #expect(fixture.reporter.runtime.ledger().isEmpty)
    }
}
