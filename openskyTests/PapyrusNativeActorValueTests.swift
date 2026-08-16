// The `Actor` natives over the *general* actor-value store (issue #468, roadmap
// item 19.5), split out of `PapyrusNativeActorTests` because that suite is at
// its size shape.
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
}
