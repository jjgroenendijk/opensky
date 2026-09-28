// Alias scripts and the alias half of the save (issue #183): a `ReferenceAlias`
// script instantiates on the reference filling its alias, retires when the
// quest stops, and comes back bound to the restored fill after a load.
//
// Every quest, script and reference is synthetic (`PapyrusQuestFixture`), so
// nothing here reads game data.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Quest alias scripts")
struct QuestAliasScriptTests {
    /// A quest carrying one forced-reference alias and one alias script, with
    /// the alias's target present in the world as a placed reference.
    private func session(
        worldState: WorldStateStore = WorldStateStore()
    ) throws -> PapyrusWorldFixture.Session {
        let quest = try PapyrusQuestFixture.quest(
            aliases: PapyrusQuestFixture.forcedAlias(),
            aliasScripts: [PapyrusQuestFixture.aliasScriptSection()]
        )
        return try PapyrusQuestFixture.session(
            quest: quest,
            objects: PapyrusQuestFixture.objects([PapyrusQuestFixture.aliasScriptObject()]),
            entries: [PapyrusWorldFixture.referenceEntry(
                objectID: PapyrusQuestFixture.aliasReferenceObjectID,
                scripts: [],
                isPersistent: true
            )],
            worldState: worldState
        )
    }

    /// The alias script is keyed by the reference in the alias, not by the
    /// quest, because that is the object a `ReferenceAlias` script runs on.
    @Test func anAliasScriptInstantiatesOnTheFilledReference() throws {
        let session = try session()
        let aliasKey = PapyrusQuestFixture.aliasInstanceKey(PapyrusQuestFixture.aliasScript)

        #expect(session.world.instancesByKey[aliasKey] != nil)
        #expect(session.world.questAliasInstanceKeys[PapyrusQuestFixture.questKey]
            == [aliasKey])
        #expect(session.world.questAliasInstanceCount == 1)
        // It is persistent and in no cell's attached set, so no detach reaches
        // it — the same rule the quest's own instances follow.
        #expect(session.world.persistentKeys.contains(aliasKey))
        session.world.detach(cell: PapyrusWorldFixture.cell)
        #expect(session.world.instancesByKey[aliasKey] != nil)

        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes.contains("alias.oninit"))
    }

    /// A quest with no filled alias instantiates no alias script at all, which
    /// is what keeps an unimplemented fill type from creating a live instance
    /// pointing at nothing.
    @Test func anUnfilledAliasCreatesNoInstance() throws {
        let quest = try PapyrusQuestFixture.quest(
            aliases: QuestFixture.alias(id: PapyrusQuestFixture.aliasID, name: "ProbeTarget"),
            aliasScripts: [PapyrusQuestFixture.aliasScriptSection()]
        )
        let session = PapyrusQuestFixture.session(
            quest: quest,
            objects: PapyrusQuestFixture.objects([PapyrusQuestFixture.aliasScriptObject()])
        )
        #expect(session.world.questAliasInstanceCount == 0)
        #expect(session.world.instancesByKey[
            PapyrusQuestFixture.aliasInstanceKey(PapyrusQuestFixture.aliasScript)
        ] == nil)
    }

    /// `Stop` retires the alias script with the quest's own, and clears the
    /// table it was bound from.
    @Test func stoppingTheQuestRetiresItsAliasScripts() throws {
        let session = try session()
        let aliasKey = PapyrusQuestFixture.aliasInstanceKey(PapyrusQuestFixture.aliasScript)
        let runtime = try #require(session.bridge.questRuntime)

        try session.bridge.stopQuest(for: PapyrusQuestFixture.questKey)

        #expect(session.world.instancesByKey[aliasKey] == nil)
        #expect(session.world.questAliasInstanceKeys.isEmpty)
        #expect(!session.world.persistentKeys.contains(aliasKey))
        #expect(try runtime.aliasState(of: PapyrusQuestFixture.questFormID).isEmpty)
        // The binding seam must not keep handing out the fills that just went.
        #expect(session.world.aliasResolution.filledAliasCount == 0)

        // Starting again refills and re-instantiates.
        #expect(try session.bridge.startQuest(for: PapyrusQuestFixture.questKey))
        #expect(session.world.instancesByKey[aliasKey] != nil)
    }

    /// A start-game-enabled quest fills at wire-up, so the Scripts readout has
    /// something to show before anything calls `Start`.
    @Test func wireUpFillsAliasesAndReportsThem() throws {
        let session = try session()
        let snapshot = session.world.scriptsSnapshot(
            runningQuestCount: 1,
            questAliasFillFailures: session.bridge.questAliasFillFailures
        )
        #expect(snapshot.filledAliasCount == 1)
        #expect(snapshot.aliasQuestCount == 1)
        #expect(snapshot.questAliasInstanceCount == 1)
        #expect(snapshot.questAliasFillFailures == 0)
        #expect(snapshot.lastQuestAliasFill != nil)

        let text = ScriptsReadout.questsText(for: snapshot)
        #expect(text.contains("Aliases filled: 1 across 1 quests"))
        #expect(text.contains("Alias instances: 1"))
    }

    /// A start-game-enabled quest whose non-optional alias will not fill is the
    /// one place OpenSky deviates: it keeps running with an empty table and
    /// counts the failure rather than un-starting itself.
    @Test func aWireUpFillFailureIsCountedRatherThanThrown() throws {
        let quest = try PapyrusQuestFixture.quest(
            aliases: PapyrusQuestFixture.forcedAlias(reference: 0)
        )
        let session = PapyrusQuestFixture.session(quest: quest)
        #expect(session.bridge.questAliasFillFailures == 1)
        #expect(try PapyrusQuestFixture.state(session).isRunning)
        #expect(session.world.aliasResolution.filledAliasCount == 0)
    }

    // MARK: - Save

    /// The table survives a save and a load, and the alias script comes back
    /// bound to the restored fill.
    @Test func aSaveRestoresTheTableAndRebindsAliasScripts() throws {
        let session = try session()
        let questKey = PapyrusQuestFixture.questKey
        let aliasKey = PapyrusQuestFixture.aliasInstanceKey(PapyrusQuestFixture.aliasScript)
        let before = try #require(session.bridge.questRuntime)
            .aliasState(of: PapyrusQuestFixture.questFormID)
        #expect(before.count == 1)

        let bytes = OpenSkySaveEncoder.encode(
            snapshot: session.worldState.snapshot(),
            fingerprint: [],
            metadata: SaveCreationMetadata(creationTimestamp: 0, appVersion: "test")
        )
        let file = try OpenSkySaveDecoder.decode(bytes)

        // A fresh session restoring that snapshot re-derives the same table and
        // instantiates the same alias instance from it.
        let restoredState = WorldStateStore()
        restoredState.restore(from: file.snapshot)
        #expect(restoredState.component(QuestAliasState.self, for: questKey) == before)

        let restored = try PapyrusQuestFixture.session(
            quest: PapyrusQuestFixture.quest(
                aliases: PapyrusQuestFixture.forcedAlias(),
                aliasScripts: [PapyrusQuestFixture.aliasScriptSection()]
            ),
            objects: PapyrusQuestFixture.objects([PapyrusQuestFixture.aliasScriptObject()]),
            entries: [PapyrusWorldFixture.referenceEntry(
                objectID: PapyrusQuestFixture.aliasReferenceObjectID,
                scripts: [],
                isPersistent: true
            )],
            worldState: restoredState
        )
        #expect(restored.world.instancesByKey[aliasKey] != nil)
        #expect(restored.world.aliasResolution.filledAliasCount == 1)
    }

    /// Determinism: a session that filled no alias writes exactly the bytes it
    /// wrote before the `QALS` chunk existed.
    @Test func aSessionWithNoFilledAliasWritesNoChunk() throws {
        let store = WorldStateStore()
        let empty = OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(),
            fingerprint: [],
            metadata: SaveCreationMetadata(creationTimestamp: 0, appVersion: "test")
        )
        #expect(!empty.contains(Data("QALS".utf8)))

        let session = try session(worldState: store)
        _ = session
        let filled = OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(),
            fingerprint: [],
            metadata: SaveCreationMetadata(creationTimestamp: 0, appVersion: "test")
        )
        #expect(filled.contains(Data("QALS".utf8)))
    }

    @Test func aLocationAliasRoundTripsInItsAdditiveChunk() throws {
        let store = WorldStateStore()
        let questKey = PapyrusQuestFixture.questKey
        let location = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x01A26F)
        store.set(
            QuestAliasState(locationFills: [
                QuestLocationAliasFill(aliasID: 7, location: location)
            ]),
            for: questKey
        )

        let bytes = OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(),
            fingerprint: [],
            metadata: SaveCreationMetadata(creationTimestamp: 0, appVersion: "test")
        )
        let decoded = try OpenSkySaveDecoder.decode(bytes)
        let state = try #require(decoded.snapshot[questKey]?.component(QuestAliasState.self))

        #expect(bytes.contains(Data("QLOC".utf8)))
        #expect(!bytes.contains(Data("QALS".utf8)))
        #expect(state.location(forAlias: 7) == location)
    }
}
