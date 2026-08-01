// InventoryBaselineResolver unit tests (issue #176): what each owner kind
// holds before anything at runtime has touched it, and how leveled entries
// expand.
//
// Every fixture is the synthetic plugin in InventoryBaselineFixture, built in
// code and read through `InventoryBaselineResolver.build(from:)`, so these
// cover the record indexing as well as the derivation.

import Foundation
@testable import opensky
import Testing

struct InventoryBaselineTests {
    private typealias Fixture = InventoryBaselineFixture

    // MARK: - Containers

    /// The chest holds three lockpicks, one gold, and one entry that is a
    /// leveled list. The list resolves deterministically — highest level wins,
    /// so the iron cuirass at level 5 beats the sword at level 1.
    @Test func containerBaselineIsItsCNTOListWithLeveledEntriesExpanded() throws {
        let resolver = try Fixture.resolver()
        let baseline = resolver.baseline(for: .container(base: Fixture.chest))
        #expect(baseline.stacks.map(\.item) == [Fixture.gold, Fixture.lockpick, Fixture.cuirass])
        #expect(baseline.count(of: Fixture.lockpick) == 3)
        #expect(baseline.count(of: Fixture.gold) == 1)
        #expect(baseline.count(of: Fixture.cuirass) == 1)
        #expect(baseline.count(of: Fixture.sword) == 0)
        // A container wears nothing.
        #expect(baseline.equipped.isEmpty)
    }

    /// A `useAll` list is a bundle rather than a choice, and the CNTO count
    /// multiplies through every entry's own count.
    @Test func useAllListsContributeEveryEntryScaledByBothCounts() throws {
        let resolver = try Fixture.resolver()
        let baseline = resolver.baseline(for: .container(base: Fixture.leveledChest))
        // CNTO count 2 over a bundle of (cuirass x1, helmet x2).
        #expect(baseline.count(of: Fixture.cuirass) == 2)
        #expect(baseline.count(of: Fixture.helmet) == 4)
    }

    @Test func emptyAndUnknownContainersBaselineEmpty() throws {
        let resolver = try Fixture.resolver()
        #expect(resolver.baseline(for: .container(base: Fixture.emptyChest)).isEmpty)
        #expect(resolver.baseline(for: .container(base: FormID(0xDEAD))).isEmpty)
    }

    // MARK: - Actors

    /// The outfit is both what the actor carries and what it is wearing:
    /// baselining a default outfit as carried-but-unworn would start every NPC
    /// naked. Slot arbitration is issue #178.
    @Test func actorBaselineIsItsResolvedDefaultOutfit() throws {
        let resolver = try Fixture.resolver()
        let baseline = resolver.baseline(for: .actor(base: Fixture.guardActor))
        // Outfit is the cuirass plus a useAll bundle of cuirass + 2 helmets,
        // so the cuirass reached twice stacks rather than appearing twice.
        #expect(baseline.count(of: Fixture.cuirass) == 2)
        #expect(baseline.count(of: Fixture.helmet) == 2)
        #expect(baseline.stacks.count == 2)
        #expect(baseline.equipped == [Fixture.cuirass, Fixture.helmet])
    }

    /// `useInventory` on a record with a template delegates the outfit upward,
    /// so the child's own DOFT is ignored and the parent's outfit is used.
    @Test func templatedActorInheritsItsParentsOutfit() throws {
        let resolver = try Fixture.resolver()
        let child = resolver.baseline(for: .actor(base: Fixture.templatedActor))
        let parent = resolver.baseline(for: .actor(base: Fixture.guardActor))
        #expect(child == parent)
        #expect(child.isEmpty == false)
    }

    @Test func actorWithNoOutfitOrABrokenChainBaselinesEmpty() throws {
        let resolver = try Fixture.resolver()
        #expect(resolver.baseline(for: .actor(base: Fixture.outfitlessActor)).isEmpty)
        #expect(resolver.baseline(for: .actor(base: FormID(0xDEAD))).isEmpty)
    }

    // MARK: - Player and generated owners

    @Test func playerAndGeneratedOwnersBaselineEmpty() throws {
        let resolver = try Fixture.resolver()
        #expect(resolver.baseline(for: .player) == .empty)
        #expect(resolver.baseline(for: .generated) == .empty)
    }

    // MARK: - Leveled expansion edge cases

    /// A list that points at itself must not recurse forever. The visited set
    /// stops it, and the form is kept as a plain stack rather than vanishing,
    /// which is the same fallback an unresolvable form gets.
    @Test func selfReferringListStopsAtTheCycleGuard() throws {
        let resolver = try Fixture.resolver()
        let baseline = resolver.baseline(for: .container(base: Fixture.chest))
        // Sanity: the fixture's other lists resolved, so this is not a
        // whole-resolver failure.
        #expect(baseline.isEmpty == false)

        let cyclic = InventoryBaselineFixture.cyclicList
        let expanded = expand(cyclic, using: resolver)
        #expect(expanded.count(of: cyclic) == 1)
    }

    /// A list with no entries contributes nothing rather than contributing
    /// itself, because the list did resolve — it simply resolved to nothing.
    @Test func emptyListContributesNothing() throws {
        let resolver = try Fixture.resolver()
        #expect(expand(Fixture.emptyList, using: resolver).isEmpty)
    }

    /// A form no index describes stays in the inventory as a plain stack: it
    /// really is in the container, it simply carries no weight or value here.
    @Test func unresolvableFormIsKeptAsAPlainStack() throws {
        let resolver = try Fixture.resolver()
        let unknown = FormID(0x00BA_DBAD)
        let expanded = expand(unknown, using: resolver)
        #expect(expanded.count(of: unknown) == 1)
        #expect(resolver.items.definition(unknown) == nil)
    }

    /// Expansion is only reachable through an owner, so a one-entry container
    /// is the probe: whatever `id` expands to is what comes out.
    private func expand(
        _ id: FormID,
        using resolver: InventoryBaselineResolver
    ) -> ReferenceInventoryState {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Probe"))
        fields += ESMFixture.field(
            "CNTO", InventoryFixture.cntoData(item: id.rawValue, count: 1)
        )
        var contents = ESMFixture.tes4()
        contents += ESMFixture.topGroup(
            "CONT", contents: ESMFixture.record("CONT", formID: 0x9000, data: fields)
        )
        guard let file = try? ESMFile(data: contents) else { return .empty }
        // The probe plugin supplies the container; the fixture resolver
        // supplies the leveled lists and item definitions being probed.
        let probe = InventoryBaselineResolver(
            items: ItemDefinitionStore(file: file),
            leveledItems: resolver.leveledItems,
            outfits: resolver.outfits,
            actors: resolver.actors
        )
        return probe.baseline(for: .container(base: FormID(0x9000)))
    }
}
