// Satellite of DestinationRegistryTests (issue #184): the World > Quests &
// Journal destination's slice of the registry contract. Split out because the
// parent file sits at the length limit, and because the conformance below has
// to live outside `FakeWorldProviders`'s own declaration for that file to stay
// there.

import AppKit
@testable import opensky
import Testing

struct DestinationRegistryJournalTests {
    /// An open journal is what "overridden" means for this destination — it
    /// sits on the menu stack and pauses world simulation — and the sidebar's
    /// reset closes it. A fresh session is closed, which the parent suite's
    /// all-destinations sweep also relies on.
    @Test @MainActor
    func journalOverrideTracksTheOpenPageAndResetClosesIt() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(DestinationRegistry.destination(id: "journal")?.overrides)
        #expect(!overrides.isOverridden(context))

        providers.openJournal()
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        #expect(providers.journal.openCount == 1)
        #expect(providers.journal.closeCount == 1)
    }

    /// Starting or advancing a quest is world state, not a panel setting: it
    /// must never light the sidebar dot, and "Reset all" must not undo it.
    @Test @MainActor
    func drivingAQuestIsNotAnOverride() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(DestinationRegistry.destination(id: "journal")?.overrides)

        providers.journalQuestEditorID = "MGRArniel01"
        providers.startSelectedQuest()
        providers.setSelectedQuestStage(10)
        providers.setSelectedQuestObjective(10, displayed: true)
        #expect(!overrides.isOverridden(context))
        #expect(providers.journal.mutations == [
            "start MGRArniel01", "stage 10", "objective 10 true"
        ])
    }

    /// The destination is placed under World, after Scripts and before the
    /// Developer group, and carries its own SF Symbol.
    @Test @MainActor
    func descriptorPlacementIsPinned() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "journal"))
        #expect(descriptor.title == "Quests & Journal")
        #expect(descriptor.section == .world)
        #expect(descriptor.symbolName == "book.closed")
        #expect(descriptor.showsGameView)
        #expect(descriptor.isWorldInspector)
        #expect(descriptor.sidebarIdentifier == "Destination-journal")

        let world = DestinationRegistry.all.filter { $0.section == .world }.map(\.id)
        let scripts = try #require(world.firstIndex(of: "scripts"))
        let journal = try #require(world.firstIndex(of: "journal"))
        #expect(journal == scripts + 1)
    }
}
