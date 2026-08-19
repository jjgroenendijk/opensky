// The `Actor` perk natives (issue #497, roadmap item 20.4): `AddPerk`,
// `RemovePerk` and `HasPerk` over a live perk runtime, plus the two refusals a
// script has to be able to tell apart.
//
// The bridge closures are the session's — a mutation goes through `PerkRuntime`
// and lands in the world-state store, so a scripted grant is saved exactly like
// a seeded one.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativePerkTests {
    /// A scripted actor plus a perk runtime wired into the bridge the way
    /// `GameViewControllerPerks` wires the session's.
    private struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let receiver: PapyrusObjectHandle
        let key: ReferenceKey
        let perks: Box
        let holder: ActorValueHolder

        /// A reference box, because the bridge closures capture the runtime and
        /// `PerkRuntime` is a struct.
        final class Box {
            var runtime: PerkRuntime
            init(_ runtime: PerkRuntime) {
                self.runtime = runtime
            }
        }
    }

    private static func fixture() throws -> Fixture {
        let entry = try PapyrusWorldFixture.actorEntry(
            objectID: 0x0004_0001,
            base: 0x0004_0002,
            scripts: [VMADFixture.Script("Bandit", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Bandit", events: [])],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(session.world)
        let (runtime, _) = try PerkRuntimeFixture.runtime(store: session.worldState)
        let box = Fixture.Box(runtime)
        let holder = ActorValueHolder(key: entry.key, subject: .actor(base: FormID(0x0004_0002)))
        session.bridge.mutatePerks = { mutation, perk, actor in
            guard actor == entry.key else { return false }
            return switch mutation {
            case .add: box.runtime.add(perk, to: holder)
            case .remove: box.runtime.remove(perk, from: holder)
            }
        }
        session.bridge.perkOwnership = { actor in
            guard actor == entry.key else { return nil }
            return Set(box.runtime.state(of: holder).owned)
        }
        let receiver = try #require(session.bridge.objectHandle(for: entry.key))
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            receiver: receiver,
            key: entry.key,
            perks: box,
            holder: holder
        )
    }

    @discardableResult
    private func call(
        _ functionName: String,
        _ fixture: Fixture,
        perk: ReferenceKey?,
        returnType: PapyrusType = .boolean
    ) -> PapyrusNativeResult {
        let handle = perk.flatMap { fixture.session.bridge.objectHandle(for: $0) }
        return fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor",
            functionName,
            receiver: fixture.receiver,
            arguments: handle.map { [PapyrusValue.object($0)] } ?? [],
            returnType: returnType
        ))
    }

    @Test func addPerkGrantsThroughTheRuntimeAndHasPerkReadsItBack() throws {
        let fixture = try Self.fixture()
        let blocking = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking)

        #expect(call("HasPerk", fixture, perk: blocking) == .returned(.boolean(false)))
        #expect(call("AddPerk", fixture, perk: blocking) == .returned(.boolean(true)))
        #expect(fixture.perks.runtime.owns(blocking, on: fixture.holder))
        #expect(call("HasPerk", fixture, perk: blocking) == .returned(.boolean(true)))
        // The grant is stored where a save reads it, not in the native.
        #expect(
            fixture.session.worldState.component(PerkState.self, for: fixture.key)?
                .owns(blocking) == true
        )
        // Adding a perk already owned answers false, which is what "True on
        // success" means for a grant that changed nothing.
        #expect(call("AddPerk", fixture, perk: blocking) == .returned(.boolean(false)))
    }

    @Test func removePerkTakesItBackOff() throws {
        let fixture = try Self.fixture()
        let blocking = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking)
        call("AddPerk", fixture, perk: blocking)

        #expect(call("RemovePerk", fixture, perk: blocking) == .returned(.boolean(true)))
        #expect(!fixture.perks.runtime.owns(blocking, on: fixture.holder))
        #expect(call("RemovePerk", fixture, perk: blocking) == .returned(.boolean(false)))
    }

    /// A call with no perk argument is a reason-tagged failure rather than a
    /// silent no-op, so the interpreter substitutes the declared default and
    /// the tally records it.
    @Test func aCallWithNoPerkArgumentFails() throws {
        let fixture = try Self.fixture()

        let result = call("AddPerk", fixture, perk: nil)

        #expect(result != .returned(.boolean(true)))
        if case .failed = result {} else {
            Issue.record("expected a reason-tagged failure, got \(result)")
        }
    }

    /// A session with no perk runtime reports the gap rather than answering
    /// "this actor has not taken it".
    @Test func hasPerkWithoutAPerkRuntimeReportsTheGap() throws {
        let fixture = try Self.fixture()
        fixture.session.bridge.perkOwnership = nil

        let result = call(
            "HasPerk", fixture, perk: PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking)
        )

        if case .failed = result {} else {
            Issue.record("expected a reason-tagged failure, got \(result)")
        }
    }
}
