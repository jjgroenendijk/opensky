// The character-level natives (issue #499, roadmap item 20.6): `Actor.GetLevel`
// and the two SKSE perk-point functions over a live level runtime, plus the
// refusals a script has to be able to tell apart.
//
// The bridge closure is the session's shape — one closure answering both
// perk-point natives, with a zero delta as the read, for the reason
// `GameViewControllerPapyrus` carries it that way.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeLevelTests {
    private struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let levels: PlayerLevelRuntime
        let playerHandle: PapyrusObjectHandle?
    }

    private static func fixture(wired: Bool = true) -> Fixture {
        let session = PapyrusWorldFixture.session(objects: [], entries: [])
        let values = ActorValueRuntime(
            store: session.worldState,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero
                )
            )
        )
        session.bridge.actorValueRuntime = { values }
        let levels = PlayerLevelRuntime(values: values)
        if wired {
            session.bridge.modifyPerkPoints = { delta in
                levels.modifyPerkPoints(by: delta).perkPoints
            }
        }
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            levels: levels,
            playerHandle: session.world.objectHandle(for: .player)
        )
    }

    @discardableResult
    private func game(
        _ functionName: String,
        _ fixture: Fixture,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusNativeCall(
            kind: .staticFunction,
            scriptName: "Game",
            functionName: functionName,
            receiver: nil,
            arguments: arguments,
            returnType: returnType
        ))
    }

    /// "The actor's current level." A fresh player is level 1, and levelling
    /// moves the number the native reports.
    @Test func getLevelReportsThePlayersCharacterLevel() throws {
        let fixture = Self.fixture()
        let receiver = try #require(fixture.playerHandle)

        #expect(
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", "GetLevel", receiver: receiver, returnType: .integer
            )) == .returned(.integer(1))
        )

        fixture.levels.award(characterExperience: 400)

        #expect(
            fixture.registry.invoke(PapyrusWorldFixture.methodCall(
                "Actor", "GetLevel", receiver: receiver, returnType: .integer
            )) == .returned(.integer(4))
        )
    }

    /// A receiver with no world identity is a refusal with a reason rather than
    /// a level of zero.
    @Test func getLevelRefusesAReceiverWithNoActor() {
        let fixture = Self.fixture()

        let result = fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", "GetLevel", receiver: nil, returnType: .integer
        ))

        #expect(PapyrusWorldFixture.isInvalidArguments(result))
    }

    /// "Returns the number of perk points available to the player."
    @Test func getPerkPointsReadsThePool() {
        let fixture = Self.fixture()
        fixture.levels.award(characterExperience: 400)

        #expect(
            game("GetPerkPoints", fixture, returnType: .integer) == .returned(.integer(3))
        )
    }

    /// The wiki's own examples: `Game.ModPerkPoints(1)` and
    /// `Game.ModPerkPoints(-3)`.
    @Test func modPerkPointsAddsAndRemoves() {
        let fixture = Self.fixture()

        #expect(game("ModPerkPoints", fixture, arguments: [.integer(5)]) == .returned(.none))
        #expect(game("GetPerkPoints", fixture, returnType: .integer) == .returned(.integer(5)))

        game("ModPerkPoints", fixture, arguments: [.integer(-3)])

        #expect(game("GetPerkPoints", fixture, returnType: .integer) == .returned(.integer(2)))
        #expect(fixture.levels.perkPoints == 2)
    }

    /// "Final values can not exceed 255."
    @Test func modPerkPointsClampsToTheDocumentedCeiling() {
        let fixture = Self.fixture()

        game("ModPerkPoints", fixture, arguments: [.integer(1000)])

        #expect(game("GetPerkPoints", fixture, returnType: .integer) == .returned(.integer(255)))
    }

    /// A missing or mistyped argument is refused rather than read as zero.
    @Test func modPerkPointsRefusesAMissingCount() {
        let fixture = Self.fixture()

        #expect(PapyrusWorldFixture.isInvalidArguments(game("ModPerkPoints", fixture)))
    }

    /// A session with no character leveling refuses both natives rather than
    /// answering zero, which would read as a player who has spent everything.
    @Test func anUnwiredSessionRefusesBothPerkPointNatives() {
        let fixture = Self.fixture(wired: false)

        #expect(PapyrusWorldFixture.isInvalidArguments(
            game("GetPerkPoints", fixture, returnType: .integer)
        ))
        #expect(PapyrusWorldFixture.isInvalidArguments(
            game("ModPerkPoints", fixture, arguments: [.integer(1)])
        ))
    }
}
