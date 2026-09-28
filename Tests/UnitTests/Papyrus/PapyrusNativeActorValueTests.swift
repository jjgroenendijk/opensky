// The `Actor` natives over the actor-value store: the general reads and writes
// of issue #468 (item 19.5) and the three base-and-modifier writes of issue
// #496 (item 20.3). Split out of `PapyrusNativeActorTests` because that suite is
// at its size shape.
//
// The fixture is that suite's, deliberately: the point of these cases is that a
// script reaching a resistance lands in the same live `ActorValueRuntime` over
// the same `WorldStateStore` a script reaching health does.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeActorValueTests {
    /// `Resist Fire`, the non-primary value these cases move.
    private static let resistFire = ActorValueIndex.resistFire

    @discardableResult
    private func call(
        _ functionName: String,
        _ fixture: PapyrusNativeActorTests.Fixture,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", functionName, receiver: fixture.receiver,
            arguments: arguments, returnType: returnType
        ))
    }

    /// Item 19.5 (issue #468): every name the vanilla table carries answers.
    /// A skill reads its documented floor and a resistance reads zero until
    /// something moves them.
    @Test func aNonPrimaryActorValueReadsItsBaseline() throws {
        let fixture = try PapyrusNativeActorTests.fixture()
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("Sneak")], returnType: .float
        ) == .returned(.float(15)))
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("Resist Fire")], returnType: .float
        ) == .returned(.float(0)))
        // Papyrus spells it without the space, and the table matches names with
        // every non-alphanumeric character dropped.
        #expect(call(
            "GetBaseActorValue", fixture,
            arguments: [.string("ResistFire")], returnType: .float
        ) == .returned(.float(0)))
    }

    /// A resistance a script raises reads back through the same natives, and
    /// damage and restore move it without touching its base.
    @Test func aNonPrimaryActorValueTakesDamageAndRestores() throws {
        let fixture = try PapyrusNativeActorTests.fixture()
        let holder = ActorValueHolder(
            key: fixture.key,
            subject: .actor(base: FormID(PapyrusNativeActorTests.baseID))
        )
        fixture.values.setValue(at: Self.resistFire, to: 60, on: holder)
        #expect(call(
            "DamageActorValue", fixture,
            arguments: [.string("Resist Fire"), .float(25)], returnType: .none
        ) == .returned(.none))
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("Resist Fire")], returnType: .float
        ) == .returned(.float(35)))
        // The base is untouched by damage, which is what makes a restore exact.
        #expect(call(
            "GetBaseActorValue", fixture,
            arguments: [.string("Resist Fire")], returnType: .float
        ) == .returned(.float(60)))
        call(
            "RestoreActorValue", fixture,
            arguments: [.string("Resist Fire"), .float(100)], returnType: .none
        )
        // Restoring undoes damage and stops there rather than climbing above
        // the base.
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("Resist Fire")], returnType: .float
        ) == .returned(.float(60)))
    }

    private func isFailure(_ result: PapyrusNativeResult) -> Bool {
        if case .failed = result {
            return true
        }
        return false
    }

    // MARK: - The three writes (issue #496, roadmap item 20.3)

    /// `SetActorValue` "sets the base value ... Any modifiers are left intact"
    /// (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>), for a primary as
    /// well as for a resistance — which is the whole reason it stayed
    /// unregistered until the primaries had a base override store.
    @Test func setActorValueWritesTheBaseAndLeavesModifiersIntact() throws {
        let fixture = try PapyrusNativeActorTests.fixture()
        let holder = ActorValueHolder(
            key: fixture.key,
            subject: .actor(base: FormID(PapyrusNativeActorTests.baseID))
        )
        fixture.values.addModifier(20, to: .temporary, at: Self.resistFire, on: holder)
        call(
            "SetActorValue", fixture,
            arguments: [.string("Resist Fire"), .float(40)], returnType: .none
        )
        #expect(call(
            "GetBaseActorValue", fixture,
            arguments: [.string("ResistFire")], returnType: .float
        ) == .returned(.float(40)))
        // The temporary modifier survived the base write, so the current value
        // is the sum rather than the number asked for.
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("ResistFire")], returnType: .float
        ) == .returned(.float(60)))

        call(
            "SetActorValue", fixture,
            arguments: [.string("Health"), .float(150)], returnType: .none
        )
        #expect(call(
            "GetBaseActorValue", fixture,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(150)))
        #expect(fixture.values.maximums(of: holder).health == 150)
    }

    /// `ModActorValue` "adjusts the maximum value for the AV, while
    /// DamageActorValue or RestoreActorValue only adjust the current value. For
    /// example, if an actor has 100 Health, ModActorValue by -10 will lower the
    /// health total to 90/90"
    /// (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>).
    @Test func modActorValueMovesTheMaximumAndTheCurrentValueTogether() throws {
        let fixture = try PapyrusNativeActorTests.fixture()
        let holder = ActorValueHolder(
            key: fixture.key,
            subject: .actor(base: FormID(PapyrusNativeActorTests.baseID))
        )
        call(
            "ModActorValue", fixture,
            arguments: [.string("Health"), .float(-10)], returnType: .none
        )
        #expect(fixture.values.maximums(of: holder).health == 90)
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(90)))
        // The base is untouched: only the permanent modifier moved.
        #expect(call(
            "GetBaseActorValue", fixture,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(100)))
    }

    /// `ForceActorValue` "modifies the 'permanent modifier' ... If an actor has
    /// a base health of 125 and you force their health to 0, then the permanent
    /// modifier will be set to -125, and their current health will become 0"
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>). A health forced to
    /// zero is a death on the same call, exactly as a fatal blow is.
    @Test func forceActorValueEmptiesTheBarAndKills() throws {
        let fixture = try PapyrusNativeActorTests.fixture()
        call(
            "ForceActorValue", fixture,
            arguments: [.string("Health"), .float(0)], returnType: .none
        )
        #expect(call(
            "GetActorValue", fixture,
            arguments: [.string("Health")], returnType: .float
        ) == .returned(.float(0)))
        #expect(call("IsDead", fixture, returnType: .boolean) == .returned(.boolean(true)))
    }

    /// The two failures every one of the three shares: a name no vanilla actor
    /// value carries, and an argument that is not a finite number.
    @Test func aWriteWithABadArgumentFailsWithAReason() throws {
        let fixture = try PapyrusNativeActorTests.fixture()
        for functionName in ["SetActorValue", "ModActorValue", "ForceActorValue"] {
            let unknown = call(
                functionName, fixture,
                arguments: [.string("Charisma"), .float(10)], returnType: .none
            )
            #expect(isFailure(unknown))
            let notANumber = call(
                functionName, fixture,
                arguments: [.string("Health"), .float(.nan)], returnType: .none
            )
            #expect(isFailure(notANumber))
        }
    }
}
