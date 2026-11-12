// The bindings that read record stores take them from the records port, and each
// native they fill reaches the session port that owns its answer.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
@testable import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldState
import Testing

@MainActor
struct ScriptRecordBindingsTests {
    private let host = ScriptHost()
    private let records = FakeWorldRecords()
    private let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
    private var adapter: ScriptWorldAdapter {
        ScriptWorldAdapter(game: host, stage: nil)
    }

    private static let actor = ReferenceKey.generated(3)

    @Test func spellNativesReachTheMagicPorts() {
        host.fakeFactionWorld.papyrusNativesResult = PapyrusFactionNatives()
        host.fakeMagic.itemUse.dispelEffectsResult = 2
        host.fakeMagic.soulTrapping.trapSoulResult = .notFilled
        host.fakeMagic.commanded = []
        adapter.perkBindings.fillSpellNatives(bridge: bridge, provider: records)
        let natives = bridge.magicNatives
        #expect(natives.casterRuntime?() == nil)
        #expect(natives.isCommandedActor?(Self.actor) == false)
        #expect(natives.dispelEffects?(.player) { _ in true } == 2)
        #expect(natives.trapSoul?(Self.actor, .player) == false)
        #expect(bridge.magicEffectStore == nil)
        #expect(bridge.keywordStore == nil)
        #expect(host.fakeMagic.soulTrapping.trapSoulCalls.map(\.victim) == [Self.actor])
    }

    @Test func theSeamsHandOverEachFeatureWorld() {
        let seams = adapter.featureBindings.seams(provider: records, worldState: WorldStateStore())
        #expect(seams.quests == nil)
        #expect(seams.inventory != nil)
        #expect(seams.objectAnimation == nil)
        #expect(seams.story != nil)
        #expect(seams.weather != nil)
        #expect(seams.music != nil)
    }

    @Test func theLeveledEditsComeFromTheRecords() {
        host.worldRecords = records
        adapter.fillPlayerNatives(bridge: bridge)
        #expect(bridge.sessionNatives.leveledEdits?() == nil)
    }

    @Test func theWorldAnswersFromTheHUDAndTheStreamer() {
        let adapter = adapter
        #expect(adapter.crosshairReference == nil)
        #expect(adapter.referenceKey(formID: FormID(0x40)) == nil)
        #expect(adapter.gameClock == nil)
        #expect(adapter.playerLocation == nil)
        #expect(host.fakeStreamer.referenceEntryFormIDCalls == [FormID(0x40)])
    }
}
