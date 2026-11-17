// `DoCombatSpellApply`: a disease rolls and is contracted without a cast, and any other
// spell needs the caster runtime. See docs/engine/diseases.md.

import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeCombatSpellApplyTests {
    private typealias Spells = SpellbookFixture

    private func apply(
        _ spell: ReferenceKey, in fixture: PapyrusNativeReferenceFixture
    ) -> PapyrusNativeResult {
        let world = fixture.session.world
        return fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Actor", "DoCombatSpellApply", receiver: fixture.receiver,
            arguments: [.object(world.objectHandle(for: spell)), .object(fixture.receiver)]
        ))
    }

    @Test func aDiseaseIsRolledInsteadOfCast() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let disease = Spells.spell(
            formID: 0x0A10, editorID: "Rockjoint", equipType: Spells.Slot.eitherHand,
            spit: Spells.spit(type: 1, chargeTime: 0, casting: 0, delivery: 0)
        )
        let plain = Spells.spell(
            formID: 0x0A11, editorID: "Sparks", equipType: Spells.Slot.eitherHand,
            spit: Spells.spit(type: 0, chargeTime: 0, casting: 1, delivery: 0)
        )
        let caster = FakeSpellCaster()
        caster.spellbook.spells = try SpellStore(
            index: Spells.index(extraRecords: [disease, plain])
        )
        fixture.session.bridge.natives.magic.casterRuntime = { caster }

        #expect(apply(Spells.key(0x0A10), in: fixture) == .returned(.none))
        guard case .failed = apply(Spells.key(0x0A11), in: fixture) else {
            Issue.record("a plain spell was cast with no caster runtime that casts")
            return
        }
    }
}
