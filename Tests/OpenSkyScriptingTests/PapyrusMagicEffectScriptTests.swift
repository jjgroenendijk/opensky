// Magic effect scripts: an MGEF's VMAD script runs while its effect runs on an actor,
// driven by active-effect writes in the world-state journal.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyMagicInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusMagicEffectScriptTests {
    private static let pluginName = "Base.esm"
    private static let effectID: UInt32 = 0x800
    private static let effectKey = ReferenceKey.plugin(name: "base.esm", objectID: effectID)
    private static let casterKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0xCCC)
    private static let effectScript = "FireEffectScript"
    private static let instanceKey = PapyrusInstanceKey(
        reference: .player,
        scriptName: effectScript
    )

    private let session: PapyrusWorldFixture.Session
    private let registry: PapyrusNativeRegistry

    init() throws {
        let lever = try PapyrusWorldFixture.referenceEntry(
            objectID: PapyrusNativeReferenceFixture.leverID,
            scripts: [VMADFixture.Script("Lever", properties: [])]
        )
        session = PapyrusWorldFixture.session(
            objects: [
                PapyrusWorldFixture.eventScript(Self.effectScript, events: [
                    ("OnInit", PapyrusWorldFixture.probeBody(note: "oninit")),
                    ("OnEffectStart", PapyrusWorldFixture.probeBody(note: "oneffectstart")),
                    ("OnEffectFinish", PapyrusWorldFixture.probeBody(note: "oneffectfinish"))
                ]),
                PapyrusWorldFixture.eventScript("Lever", events: [
                    ("OnMagicEffectApply", PapyrusWorldFixture.probeBody(note: "lever.apply"))
                ])
            ],
            entries: [lever]
        )
        PapyrusWorldFixture.drain(session.world)
        session.bridge.magicEffectStore = try Self.store()
        session.bridge.queueMagicEffectEvents()
        registry = PapyrusWorldFixture.registry(for: session)
    }

    private static func store() throws -> MagicEffectStore {
        let vmad = VMADFixture.payload(scripts: [VMADFixture.Script(effectScript, properties: [])])
        let record = ESMFixture.record(
            "MGEF",
            formID: effectID,
            data: ESMFixture.field("EDID", ESMFixture.zstring("FireEffect"))
                + ESMFixture.field("VMAD", vmad)
                + ESMFixture.field("DATA", MagicEffectFixture.data())
        )
        let file = try ESMFixture.plugin(records: [record])
        return MagicEffectStore(plugins: [(pluginName, file)])
    }

    private static func effect(
        sequence: UInt64,
        caster: ReferenceKey? = casterKey
    ) -> ActiveEffect {
        ActiveEffect(
            sequence: sequence,
            source: ActiveEffectSource(kind: .spell, record: effectKey),
            effect: effectKey,
            caster: caster,
            mode: .modifier,
            isDetrimental: true,
            duration: 5,
            values: [ActiveEffectValue(index: -1, magnitude: 10)]
        )
    }

    private func write(_ effects: [ActiveEffect], on key: ReferenceKey = .player) {
        if effects.isEmpty {
            session.worldState.reset(.activeEffects, for: key)
        } else {
            session.worldState.set(ActiveEffectState(effects: effects), for: key)
        }
        session.bridge.queueMagicEffectEvents()
        PapyrusWorldFixture.drain(session.world)
    }

    private func call(_ name: String, script: String = "ActiveMagicEffect") -> PapyrusNativeResult {
        registry.invoke(PapyrusWorldFixture.methodCall(
            script, name, receiver: session.world.instancesByKey[Self.instanceKey]
        ))
    }

    @Test func startingEffectRunsInitThenStartAndEndingItRunsFinishThenRetires() {
        write([Self.effect(sequence: 1)])
        #expect(session.dispatch.notes == ["oninit", "oneffectstart"])
        #expect(session.world.instancesByKey[Self.instanceKey] != nil)

        write([])
        #expect(session.dispatch.notes == ["oninit", "oneffectstart", "oneffectfinish"])
        #expect(session.world.instancesByKey[Self.instanceKey] == nil)
        #expect(session.world.effectScripts.instanceKeys.isEmpty)
    }

    @Test func aLaterRunMakesAFreshInstanceWithItsOwnInit() {
        write([Self.effect(sequence: 1)])
        write([])
        write([Self.effect(sequence: 2)])
        #expect(session.dispatch.notes.filter { $0 == "oninit" }.count == 2)
    }

    @Test func twoRunsShareOneInstanceUntilTheLastEnds() {
        write([Self.effect(sequence: 1), Self.effect(sequence: 2)])
        write([Self.effect(sequence: 2)])
        #expect(session.world.instancesByKey[Self.instanceKey] != nil)
        write([])
        #expect(session.world.instancesByKey[Self.instanceKey] == nil)
        #expect(session.dispatch.notes.filter { $0 == "oneffectfinish" }.count == 2)
    }

    @Test func nativesAnswerForTheRunAndTheInstanceIsNotTheActorsScript() throws {
        write([Self.effect(sequence: 1)])
        let world = session.world
        let instance = try #require(world.instancesByKey[Self.instanceKey])
        #expect(world.objectHandle(for: .player) != instance)
        #expect(call("GetTargetActor") == .returned(.object(world.objectHandle(for: .player))))
        #expect(call("GetCasterActor") ==
            .returned(.object(world.objectHandle(for: Self.casterKey))))
        #expect(call("GetBaseObject") ==
            .returned(.object(world.objectHandle(for: Self.effectKey))))
    }

    @Test func dispelRemovesOnlyThisEffect() {
        write([Self.effect(sequence: 1)])
        var removed: [UInt64] = []
        session.bridge.magicNatives.dispelEffects = { _, predicate in
            let doomed = [Self.effect(sequence: 1), Self.effect(sequence: 7)].filter(predicate)
            removed = doomed.map(\.sequence)
            return doomed.count
        }
        #expect(call("Dispel") == .returned(.none))
        #expect(removed == [1])
    }

    @Test func nativesFailWithoutARunningEffect() {
        #expect(PapyrusWorldFixture.isInvalidArguments(call("GetTargetActor")))
    }

    @Test func targetScriptsHearMagicEffectApply() {
        write([Self.effect(sequence: 1)], on: PapyrusNativeReferenceFixture.key(
            PapyrusNativeReferenceFixture.leverID
        ))
        #expect(session.dispatch.notes.first == "lever.apply")
    }

    @Test func associatedSkillNamesTheMagicSkill() {
        let result = registry.invoke(PapyrusWorldFixture.methodCall(
            "MagicEffect", "GetAssociatedSkill",
            receiver: session.world.objectHandle(for: Self.effectKey)
        ))
        // `MagicEffectFixture.data()` names actor value 20 as the magic skill.
        #expect(result == .returned(.string("Destruction")))
    }
}
