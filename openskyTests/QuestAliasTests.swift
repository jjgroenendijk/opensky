// Quest alias resolution (issue #183, roadmap item 13.4): the fill pass, the
// documented rules it implements, and the table's lifetime on the store.
//
// Every quest is synthetic, built out of `QuestFixture` bytes, so nothing here
// reads game data. The store is @MainActor, so the suite is too.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Quest aliases")
struct QuestAliasTests {
    private let quest = FormID(0x0100)
    private let arniel = FormID(0x0500)
    private let book = FormID(0x0501)

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }

    /// One quest with two forced-reference aliases: a required actor and an
    /// optional item.
    private func store(
        aliases: Data,
        flags: UInt16 = 0
    ) throws -> QuestStore {
        try QuestFixture.store(QuestFixture.record(
            formID: 0x0100,
            fields: QuestFixture.editorID("MGRArniel01")
                + QuestFixture.general(flags: flags, type: 1)
                + QuestFixture.stage(10, flags: 0x02)
                + QuestFixture.logEntry(text: "start")
                + QuestFixture.marker("ANAM")
                + aliases
        ))
    }

    private func runtime(
        _ store: WorldStateStore,
        aliases: Data,
        flags: UInt16 = 0
    ) throws -> QuestRuntime {
        try QuestRuntime(store: store, quests: self.store(aliases: aliases, flags: flags))
    }

    /// ALFR — the one fill type item 13.4 implements.
    private func forced(
        id: UInt32,
        name: String,
        reference: FormID,
        flags: UInt32 = 0,
        extras: Data = Data()
    ) -> Data {
        QuestFixture.alias(
            id: id,
            name: name,
            flags: flags,
            fill: QuestFixture.word("ALFR", reference.rawValue),
            extras: extras
        )
    }

    // MARK: - Filling

    /// The documented base case: a specific reference lands in its alias when
    /// the quest starts, and not before.
    @Test func aStartFillsForcedReferenceAliases() throws {
        let store = WorldStateStore()
        let quests = try runtime(
            store,
            aliases: forced(id: 0, name: "Arniel", reference: arniel)
                + forced(id: 1, name: "Book", reference: book)
        )

        #expect(try quests.aliasState(of: quest).isEmpty)
        try quests.startQuest(quest)

        let table = try quests.aliasState(of: quest)
        #expect(table.count == 2)
        #expect(table.reference(forAlias: 0) == key(0x0500))
        #expect(table.reference(forAlias: 1) == key(0x0501))
        #expect(quests.aliasReference(alias: 0, in: quest) == key(0x0500))
        // Filling is a world-state write like any other, so it is journalled.
        #expect(store.journalEntries.contains { $0.kind == .questAliases })
    }

    /// "Aliases are filled in order", and a forced-into target takes the value
    /// of the *last* source alias that fills it, not the first.
    @Test func fillOrderIsListOrderAndForceIntoAliasTakesTheLastWriter() throws {
        let store = WorldStateStore()
        let quests = try runtime(
            store,
            aliases: forced(
                id: 0, name: "Fallback", reference: book,
                extras: QuestFixture.signedWord("ALFI", 2)
            )
                + forced(
                    id: 1, name: "Preferred", reference: arniel,
                    extras: QuestFixture.signedWord("ALFI", 2)
                )
                + QuestFixture.alias(id: 2, name: "Target", flags: 0x02)
        )
        try quests.startQuest(quest)

        let table = try quests.aliasState(of: quest)
        #expect(table.reference(forAlias: 0) == key(0x0501))
        #expect(table.reference(forAlias: 1) == key(0x0500))
        // Alias 2 was forced into twice; the later source in the list won.
        #expect(table.reference(forAlias: 2) == key(0x0500))
    }

    /// An alias flagged Optional may stay empty; the quest still starts.
    @Test func anOptionalAliasMayStayEmpty() throws {
        let store = WorldStateStore()
        // ALFR naming the null FormID resolves to nothing, which is the one
        // implemented fill type failing rather than an unimplemented one.
        let quests = try runtime(
            store,
            aliases: forced(id: 0, name: "Arniel", reference: arniel)
                + forced(id: 1, name: "Book", reference: FormID(0), flags: 0x02)
        )
        try quests.startQuest(quest)

        let table = try quests.aliasState(of: quest)
        #expect(table.count == 1)
        #expect(table.reference(forAlias: 1) == nil)
        #expect(try quests.state(of: quest).isRunning)
    }

    /// "If unchecked, the quest will fail to start if it cannot fill this
    /// alias." Nothing is written when it does.
    @Test func aNonOptionalAliasThatCannotFillRefusesTheStart() throws {
        let store = WorldStateStore()
        let quests = try runtime(
            store,
            aliases: forced(id: 0, name: "Arniel", reference: arniel)
                + forced(id: 1, name: "Book", reference: FormID(0))
        )

        #expect(throws: QuestError.aliasFillFailed(quest: quest, aliases: [1])) {
            try quests.startQuest(quest)
        }
        #expect(try quests.aliasState(of: quest).isEmpty)
        #expect(try !quests.state(of: quest).isRunning)
        #expect(store.dirtyCount == 0)
    }

    /// A start-up stage starts the quest, so it fills and refuses on the same
    /// rule `startQuest` does.
    @Test func aStartUpStageIsRefusedByTheSameRule() throws {
        let store = WorldStateStore()
        let quests = try runtime(
            store, aliases: forced(id: 0, name: "Arniel", reference: FormID(0))
        )

        #expect(throws: QuestError.aliasFillFailed(quest: quest, aliases: [0])) {
            try quests.setStage(10, on: quest)
        }
        #expect(try !quests.state(of: quest).isStageDone(10))
    }

    /// A fill type OpenSky does not implement is a counted skip, never a start
    /// failure: refusing the quest would dress an engine gap as game semantics.
    @Test func anUnimplementedFillTypeIsATalliedSkip() throws {
        let store = WorldStateStore()
        let quests = try runtime(
            store,
            aliases: QuestFixture.alias(
                id: 0, name: "Nearest", fill: QuestFixture.word("ALUA", 0x0700)
            )
                + QuestFixture.alias(id: 1, name: "Where", location: true)
        )
        let record = try #require(quests.quests.quest(quest))
        let result = QuestAliasFiller.fill(record, resolver: quests.quests.resolver)

        #expect(result.state.isEmpty)
        #expect(result.canStartQuest)
        #expect(result.skipped.total == 2)
        #expect(result.skipped.counts[.unsupportedFillType(.uniqueActor)] == 1)
        #expect(result.skipped.counts[.locationAlias] == 1)
        #expect(result.skipped.ranked.first?.name == "location alias")

        try quests.startQuest(quest)
        #expect(try quests.state(of: quest).isRunning)
    }

    /// "Normally, the game will not fill two aliases on the same quest with the
    /// same reference", and the flag that lifts it is checked on the second.
    @Test func oneReferenceFillsTwoAliasesOnlyWithAllowReuse() throws {
        let store = WorldStateStore()
        let refused = try runtime(
            store,
            aliases: forced(id: 0, name: "First", reference: arniel)
                + forced(id: 1, name: "Second", reference: arniel, flags: 0x02)
        )
        try refused.startQuest(quest)
        #expect(try refused.aliasState(of: quest).count == 1)
        // Refusing the fill never refuses the start: thirteen vanilla quests
        // reuse a reference without the flag, so `QuestAliasFiller` counts the
        // refusal instead of blocking them.
        #expect(try refused.state(of: quest).isRunning)

        let allowed = try QuestRuntime(
            store: WorldStateStore(),
            quests: self.store(
                aliases: forced(id: 0, name: "First", reference: arniel)
                    + forced(id: 1, name: "Second", reference: arniel, flags: 0x08)
            )
        )
        try allowed.startQuest(quest)
        #expect(try allowed.aliasState(of: quest).count == 2)
    }

    // MARK: - Lifetime

    /// Aliases hold nothing before a start and nothing after a stop, while the
    /// reached stages survive both.
    @Test func stoppingClearsTheTableAndRestartingRefillsIt() throws {
        let store = WorldStateStore()
        let quests = try runtime(store, aliases: forced(id: 0, name: "Arniel", reference: arniel))
        try quests.startQuest(quest)
        try quests.setStage(10, on: quest)

        try quests.stopQuest(quest)
        #expect(try quests.aliasState(of: quest).isEmpty)
        #expect(try quests.state(of: quest).isStageDone(10))

        try quests.startQuest(quest)
        #expect(try quests.aliasState(of: quest).reference(forAlias: 0) == key(0x0500))
    }

    /// A second `Start` on a running quest must not re-point aliases its
    /// scripts are already holding.
    @Test func startingARunningQuestKeepsTheTableItHas() throws {
        let store = WorldStateStore()
        let quests = try runtime(store, aliases: forced(id: 0, name: "Arniel", reference: arniel))
        try quests.startQuest(quest)
        let before = try quests.aliasState(of: quest)
        try quests.startQuest(quest)
        #expect(try quests.aliasState(of: quest) == before)
    }

    /// Resetting a quest to plugin data drops the table with the state: a quest
    /// that has not started holds nothing in its aliases.
    @Test func resettingAQuestDropsItsTable() throws {
        let store = WorldStateStore()
        let quests = try runtime(store, aliases: forced(id: 0, name: "Arniel", reference: arniel))
        try quests.startQuest(quest)
        #expect(quests.reset(quest))
        #expect(try quests.aliasState(of: quest).isEmpty)
        #expect(store.dirtyCount == 0)
    }

    // MARK: - Seams

    /// The resolution seam answers by number and by authored name, and reports
    /// an unfilled alias as nil rather than as no quest.
    @Test func theResolutionSeamAnswersByNumberAndByName() throws {
        let store = WorldStateStore()
        let quests = try runtime(
            store,
            aliases: forced(id: 0, name: "Arniel", reference: arniel)
                + forced(id: 1, name: "Book", reference: FormID(0), flags: 0x02)
        )
        try quests.startQuest(quest)
        let aliases = quests.aliasResolution()

        #expect(aliases.reference(alias: 0, in: quest) == key(0x0500))
        #expect(aliases.reference(aliasNamed: "arniel", in: quest) == key(0x0500))
        #expect(aliases.aliasID(named: "Book", in: quest) == 1)
        #expect(aliases.reference(aliasNamed: "Book", in: quest) == nil)
        #expect(aliases.reference(aliasNamed: "NoSuchAlias", in: quest) == nil)
        #expect(aliases.table(for: FormID(0x9999)) == nil)
        #expect(aliases.filledQuestCount == 1)
        #expect(aliases.filledAliasCount == 1)

        // Off the main actor, the same answers come out of a snapshot.
        let snapshot = QuestAliasResolution(
            defaults: quests.quests, snapshot: store.snapshot()
        )
        #expect(snapshot.reference(alias: 0, in: quest) == key(0x0500))
    }

    /// The component normalizes on the way in, which is what keeps two stores
    /// that filled the same aliases byte-identical.
    @Test func theComponentSortsAndDeduplicatesItsFills() {
        let state = QuestAliasState(fills: [
            QuestAliasFill(aliasID: 5, reference: key(0x0500)),
            QuestAliasFill(aliasID: 1, reference: key(0x0501)),
            QuestAliasFill(aliasID: 5, reference: key(0x0502))
        ])
        #expect(state.fills.map(\.aliasID) == [1, 5])
        #expect(state.reference(forAlias: 5) == key(0x0502))
        #expect(state.holds(key(0x0501)))
        #expect(!state.holds(key(0x0500)))
    }
}
