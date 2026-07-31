// `Game.GetPlayer` (issue #172): the one `Game` native with an engine behind
// it, and the way a script names the player.
//
// Fixtures are built in code — never extracted game files (AGENTS.md "Legal &
// IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeGameTests {
    private func session() throws -> PapyrusWorldFixture.Session {
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: 0x0000_0AAA,
            scripts: [VMADFixture.Script("Lever", properties: [])]
        )
        let built = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Lever", events: [])],
            entries: [entry]
        )
        PapyrusWorldFixture.drain(built.world)
        return built
    }

    private func getPlayer(_ registry: PapyrusNativeRegistry) -> PapyrusNativeResult {
        registry.invoke(PapyrusNativeCall(
            kind: .staticFunction,
            scriptName: "Game",
            functionName: "GetPlayer",
            receiver: nil,
            arguments: [],
            returnType: .object("Actor")
        ))
    }

    /// The handle names `ReferenceKey.player` and is the same on every call, so
    /// script code comparing it against an `akActionRef` gets the right answer.
    @Test func getPlayerReturnsTheStableHandleForThePlayerKey() throws {
        let session = try session()
        let registry = PapyrusWorldFixture.registry(for: session)
        let result = getPlayer(registry)
        guard case let .returned(.object(handle)) = result else {
            Issue.record("GetPlayer did not return an object: \(result)")
            return
        }
        #expect(session.world.referenceKey(for: handle) == .player)
        #expect(ReferenceKey.player == .generated(0))
        #expect(getPlayer(registry) == .returned(.object(handle)))
    }

    /// The player's activation of a reference names the same handle
    /// `GetPlayer` hands out, which is what makes the usual
    /// `akActionRef == Game.GetPlayer()` guard work.
    @Test func getPlayerMatchesTheActivatorAnOnActivateReceives() throws {
        let session = try session()
        let registry = PapyrusWorldFixture.registry(for: session)
        let result = getPlayer(registry)
        guard case let .returned(.object(handle)) = result else {
            Issue.record("GetPlayer did not return an object: \(result)")
            return
        }
        #expect(session.world.objectHandle(for: session.bridge.playerKey) == handle)
    }

    @Test func headlessGetPlayerFails() {
        #expect(PapyrusWorldFixture.isInvalidArguments(
            getPlayer(PapyrusNativeRegistry.standard)
        ))
    }
}
