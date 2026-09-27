// The `Game` skill natives (issue #498, roadmap item 20.5): `AdvanceSkill` and
// `IncrementSkill` over a live advancement runtime, plus the refusals a script
// has to be able to tell apart.
//
// The bridge closure is the session's shape — the whole read-modify-write, for
// the reason `GameViewControllerSkills` carries it: `SkillAdvancementRuntime`
// is a struct, and handing the bridge a copy would drop the write.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeSkillTests {
    /// Archery, whose Papyrus name is the editor-id spelling `Marksman`.
    private static let archery: Int32 = 8

    private final class Box {
        var runtime: SkillAdvancementRuntime
        init(_ runtime: SkillAdvancementRuntime) {
            self.runtime = runtime
        }
    }

    private struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let skills: Box
    }

    private static func fixture(wired: Bool = true) -> Fixture {
        let session = PapyrusWorldFixture.session(objects: [], entries: [])
        let values = ActorValueRuntime(
            store: session.worldState,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero,
                    general: [archery: 15]
                )
            )
        )
        let box = Box(SkillAdvancementRuntime(
            values: values,
            parameters: SkillUseParameterSource(table: [
                archery: SkillUseParameters(
                    useMultiplier: 9.3,
                    useOffset: 0,
                    improveMultiplier: 2,
                    improveOffset: 0
                )
            ])
        ))
        if wired {
            session.bridge.advanceSkill = { advance, index, magnitude in
                let report = switch advance {
                case .advance:
                    box.runtime.advance(
                        skill: index, byUse: magnitude, on: box.runtime.player
                    )
                case .increment:
                    box.runtime.increment(skill: index, on: box.runtime.player)
                }
                return report != nil
            }
        }
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            skills: box
        )
    }

    @discardableResult
    private func call(
        _ functionName: String,
        _ fixture: Fixture,
        arguments: [PapyrusValue]
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusNativeCall(
            kind: .staticFunction,
            scriptName: "Game",
            functionName: functionName,
            receiver: nil,
            arguments: arguments,
            returnType: .none
        ))
    }

    /// The wiki's own example: `Game.AdvanceSkill("Marksman", 50.0)`, which is
    /// fifty skill *uses* rather than fifty experience.
    @Test func advanceSkillConvertsAUseAmount() {
        let fixture = Self.fixture()

        let result = call(
            "AdvanceSkill", fixture, arguments: [.string("Marksman"), .float(50)]
        )

        // 50 * 9.3 = 465 experience, which is more than the 2 * 15^1.95 = 393.01
        // Archery needs to leave level 15, so the skill goes up and the
        // remainder stays on it.
        #expect(result == .returned(.none))
        #expect(fixture.skills.runtime.level(ofSkill: Self.archery, on: .player) == 16)
        let carried = fixture.skills.runtime.experience(forSkill: Self.archery, on: .player)
        #expect(abs(carried - 71.99) < 0.05)
    }

    /// One whole point, and the experience earned by use is left alone.
    @Test func incrementSkillRaisesTheSkillByOne() {
        let fixture = Self.fixture()
        call("AdvanceSkill", fixture, arguments: [.string("Marksman"), .float(1)])

        let result = call("IncrementSkill", fixture, arguments: [.string("Marksman")])

        #expect(result == .returned(.none))
        #expect(fixture.skills.runtime.level(ofSkill: Self.archery, on: .player) == 16)
        #expect(
            fixture.skills.runtime.experience(forSkill: Self.archery, on: .player) == 9.3
        )
    }

    /// "The amount must be positive."
    @Test func advanceSkillRefusesANonPositiveMagnitude() {
        let fixture = Self.fixture()

        let result = call(
            "AdvanceSkill", fixture, arguments: [.string("Marksman"), .float(0)]
        )

        #expect(PapyrusWorldFixture.isInvalidArguments(result))
    }

    /// A name that is not one of the eighteen skills is refused rather than
    /// written to a neighbouring actor value.
    @Test func aNonSkillNameIsRefused() {
        let fixture = Self.fixture()

        let result = call(
            "AdvanceSkill", fixture, arguments: [.string("Health"), .float(10)]
        )

        #expect(PapyrusWorldFixture.isInvalidArguments(result))
    }

    /// A session with no progression reports the gap rather than letting a
    /// script believe it taught the player something.
    @Test func aSessionWithNoProgressionReportsTheGap() {
        let fixture = Self.fixture(wired: false)

        let result = call(
            "IncrementSkill", fixture, arguments: [.string("Marksman")]
        )

        #expect(PapyrusWorldFixture.isInvalidArguments(result))
    }
}
