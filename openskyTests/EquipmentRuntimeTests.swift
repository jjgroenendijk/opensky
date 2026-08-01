// Equip/unequip runtime (issue #178, roadmap item 12.2.1): the slot-conflict
// matrix, the round-trips, the two typed refusals, and the accounting an equip
// must leave alone.
//
// The catalog is built by `EquipmentCatalog.build(from:)` over
// `InventoryBaselineFixture`'s synthetic plugin, so these tests exercise the
// real ARMO/WEAP indexing path rather than a hand-assembled dictionary. The
// plugin is assembled in code from published record layouts — never extracted
// game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct EquipmentRuntimeTests {
    private typealias Fixture = InventoryBaselineFixture

    private func makeRuntime(_ store: WorldStateStore) throws -> EquipmentRuntime {
        try EquipmentRuntime(
            inventory: InventoryRuntime(store: store, baselines: Fixture.resolver()),
            catalog: EquipmentCatalog.build(from: ESMFile(data: Fixture.pluginBytes()))
        )
    }

    /// A holder with nothing in its baseline, so a test controls exactly what
    /// it holds. The player's baseline is empty by definition.
    private let player = InventoryHolder.player

    // MARK: - Catalog

    @Test func catalogIndexesArmourSlotsAndWeaponHands() throws {
        let catalog = try EquipmentCatalog.build(from: ESMFile(data: Fixture.pluginBytes()))

        #expect(catalog.occupancy(of: Fixture.cuirass).slots == .body)
        #expect(catalog.occupancy(of: Fixture.helmet).slots == .head)
        #expect(catalog.occupancy(of: Fixture.gauntlets).slots == .hands)
        #expect(catalog.occupancy(of: Fixture.sword).hands == .rightHand)
        #expect(catalog.occupancy(of: Fixture.greatsword).hands == .bothHands)
        // Armour occupies no hands and weapons no biped slots.
        #expect(catalog.occupancy(of: Fixture.cuirass).hands.isEmpty)
        #expect(catalog.occupancy(of: Fixture.sword).slots.isEmpty)
        // A weapon carries the model path a hand attachment loads.
        #expect(catalog.item(Fixture.sword)?.modelPath == "weapons\\iron\\sword.nif")
        #expect(catalog.item(Fixture.cuirass)?.modelPath == nil)
    }

    @Test func catalogDoesNotDescribeNonEquippableItems() throws {
        let catalog = try EquipmentCatalog.build(from: ESMFile(data: Fixture.pluginBytes()))

        #expect(catalog.item(Fixture.lockpick) == nil)
        #expect(catalog.occupancy(of: Fixture.lockpick).isEmpty)
        #expect(catalog.occupancy(of: FormID(0xDEAD)).isEmpty)
    }

    // MARK: - Slot conflicts

    @Test func equippingATorsoPieceDisplacesTheOtherOne() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        for item in [Fixture.cuirass, Fixture.leatherCuirass] {
            try equipment.inventory.add(item, count: 1, to: player)
        }

        try equipment.equip(Fixture.cuirass, on: player)
        let change = try equipment.equip(Fixture.leatherCuirass, on: player)

        #expect(change.unequipped == [Fixture.cuirass])
        #expect(change.changed)
        #expect(equipment.equipped(on: player) == [Fixture.leatherCuirass])
    }

    @Test func equippingDisjointSlotsKeepsBoth() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        for item in [Fixture.cuirass, Fixture.helmet, Fixture.gauntlets] {
            try equipment.inventory.add(item, count: 1, to: player)
            try equipment.equip(item, on: player)
        }

        // Sorted ascending by FormID, which is what the component guarantees.
        #expect(equipment.equipped(on: player)
            == [Fixture.cuirass, Fixture.helmet, Fixture.gauntlets])
    }

    @Test func twoHandedWeaponDisplacesTheOneHandedOne() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        for item in [Fixture.sword, Fixture.greatsword] {
            try equipment.inventory.add(item, count: 1, to: player)
        }

        try equipment.equip(Fixture.sword, on: player)
        let change = try equipment.equip(Fixture.greatsword, on: player)

        #expect(change.unequipped == [Fixture.sword])
        #expect(equipment.equipped(on: player) == [Fixture.greatsword])
    }

    @Test func weaponsAndArmourNeverConflict() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        for item in [Fixture.cuirass, Fixture.sword] {
            try equipment.inventory.add(item, count: 1, to: player)
        }

        try equipment.equip(Fixture.cuirass, on: player)
        let change = try equipment.equip(Fixture.sword, on: player)

        #expect(change.unequipped.isEmpty)
        // Ascending FormID: the sword is 0x0200 and the cuirass 0x0300.
        #expect(equipment.equipped(on: player) == [Fixture.sword, Fixture.cuirass])
    }

    @Test func oneEquipDisplacesEveryConflictingPieceAtOnce() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        // Both torso pieces worn at once is not reachable through `equip`, so
        // the equipped set is seeded directly to prove the resolution covers a
        // set it did not build itself — a save from an older build, say.
        for item in [Fixture.cuirass, Fixture.leatherCuirass, Fixture.helmet] {
            try equipment.inventory.add(item, count: 1, to: player)
        }
        equipment.inventory.setEquipped([Fixture.cuirass, Fixture.helmet], on: player)

        let change = try equipment.equip(Fixture.leatherCuirass, on: player)

        #expect(change.unequipped == [Fixture.cuirass])
        #expect(equipment.equipped(on: player) == [Fixture.helmet, Fixture.leatherCuirass])
    }

    @Test func equippingWhatIsAlreadyWornChangesNothing() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        try equipment.inventory.add(Fixture.cuirass, count: 1, to: player)
        try equipment.equip(Fixture.cuirass, on: player)
        let before = store.snapshot().sequence

        let change = try equipment.equip(Fixture.cuirass, on: player)

        #expect(change.unequipped.isEmpty)
        #expect(!change.changed)
        #expect(store.snapshot().sequence == before)
    }

    // MARK: - Round-trip

    @Test func equipUnequipRoundTripsAndKeepsTheItemCarried() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        try equipment.inventory.add(Fixture.sword, count: 1, to: player)

        try equipment.equip(Fixture.sword, on: player)
        #expect(equipment.isEquipped(Fixture.sword, on: player))
        #expect(equipment.unequip(Fixture.sword, on: player))

        #expect(equipment.equipped(on: player).isEmpty)
        #expect(equipment.inventory.count(of: Fixture.sword, in: player) == 1)
    }

    @Test func unequippingSomethingNotWornIsNotAnError() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        try equipment.inventory.add(Fixture.sword, count: 1, to: player)

        #expect(!equipment.unequip(Fixture.sword, on: player))
        #expect(equipment.equipped(on: player).isEmpty)
    }

    @Test func unequipAllStripsEverything() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        for item in [Fixture.cuirass, Fixture.helmet, Fixture.sword] {
            try equipment.inventory.add(item, count: 1, to: player)
            try equipment.equip(item, on: player)
        }

        #expect(equipment.unequipAll(on: player))
        #expect(equipment.equipped(on: player).isEmpty)
    }

    /// An actor baselines its equipped set to its default outfit, so the first
    /// equip must add to that rather than replace it — otherwise equipping a
    /// helmet would strip the NPC to it.
    @Test func firstEquipOnAnActorKeepsTheDefaultOutfitOn() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        let guard0 = InventoryHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0BAD),
            owner: .actor(base: Fixture.guardActor),
            cell: nil
        )
        let outfit = equipment.equipped(on: guard0)
        #expect(outfit.contains(Fixture.cuirass))
        try equipment.inventory.add(Fixture.sword, count: 1, to: guard0)

        try equipment.equip(Fixture.sword, on: guard0)

        #expect(equipment.equipped(on: guard0) == (outfit + [Fixture.sword]).sorted {
            $0.rawValue < $1.rawValue
        })
    }

    // MARK: - Refusals

    @Test func equippingSomethingNotHeldIsATypedFailureAndWritesNothing() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        let before = store.snapshot().sequence

        #expect(throws: EquipmentError.notHeld(item: Fixture.sword, owner: .player)) {
            try equipment.equip(Fixture.sword, on: player)
        }
        #expect(store.snapshot().sequence == before)
        #expect(equipment.equipped(on: player).isEmpty)
    }

    @Test func equippingSomethingWithNoSlotsIsATypedFailure() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        try equipment.inventory.add(Fixture.lockpick, count: 1, to: player)

        #expect(throws: EquipmentError.notEquippable(item: Fixture.lockpick)) {
            try equipment.equip(Fixture.lockpick, on: player)
        }
        #expect(equipment.equipped(on: player).isEmpty)
    }

    @Test func equippingAFormNoPluginDescribesIsNotEquippable() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        let unknown = FormID(0xDEAD)
        try equipment.inventory.add(unknown, count: 1, to: player)

        #expect(throws: EquipmentError.notEquippable(item: unknown)) {
            try equipment.equip(unknown, on: player)
        }
    }

    // MARK: - Journalling and accounting

    @Test func oneEquipIsOneJournalledWriteHoweverMuchItDisplaces() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        for item in [Fixture.cuirass, Fixture.leatherCuirass] {
            try equipment.inventory.add(item, count: 1, to: player)
        }
        try equipment.equip(Fixture.cuirass, on: player)
        let before = store.snapshot().sequence

        try equipment.equip(Fixture.leatherCuirass, on: player)

        #expect(store.snapshot().sequence == before + 1)
    }

    /// Equipping moves nothing between owners, so carry weight is unchanged —
    /// worn armour is still carried armour. With no rendered player body this
    /// milestone, state plus this accounting is the whole player half.
    @Test func equippingDoesNotChangeCarriedWeightOrValue() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        try equipment.inventory.add(Fixture.cuirass, count: 1, to: player)
        let weight = equipment.inventory.carriedWeight(of: player)
        let value = equipment.inventory.carriedValue(of: player)

        try equipment.equip(Fixture.cuirass, on: player)

        #expect(equipment.inventory.carriedWeight(of: player) == weight)
        #expect(equipment.inventory.carriedValue(of: player) == value)
        #expect(weight == 30)
    }

    /// The write is attributed to the owner's cell, which is what makes
    /// `CellStreamer.noteStateMutation` rebuild that one cell and no other.
    @Test func equipIsAttributedToTheOwnersCell() throws {
        let store = WorldStateStore()
        let equipment = try makeRuntime(store)
        let cell = CellSceneLocation.exterior(CellCoordinate(x: 5, y: -1))
        let actor = InventoryHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0BAD),
            owner: .actor(base: Fixture.outfitlessActor),
            cell: cell
        )
        try equipment.inventory.add(Fixture.helmet, count: 1, to: actor)

        try equipment.equip(Fixture.helmet, on: actor)

        #expect(store.journalEntries.last?.cell == cell)
        #expect(store.journalEntries.last?.kind == .inventory)
    }
}

struct EquipmentOccupancyTests {
    @Test func conflictNeedsAnOverlapInEitherHalf() {
        let torso = EquipmentOccupancy(slots: .body)
        let alsoTorso = EquipmentOccupancy(slots: [.body, .forearms])
        let hands = EquipmentOccupancy(slots: .hands)
        let right = EquipmentOccupancy(hands: .rightHand)
        let both = EquipmentOccupancy(hands: .bothHands)
        let left = EquipmentOccupancy(hands: .leftHand)

        #expect(torso.conflicts(with: alsoTorso))
        #expect(!torso.conflicts(with: hands))
        #expect(!torso.conflicts(with: right))
        #expect(right.conflicts(with: both))
        #expect(!right.conflicts(with: left))
        #expect(left.conflicts(with: both))
    }

    @Test func nothingOccupiesNothingAndConflictsWithNothing() {
        #expect(EquipmentOccupancy.none.isEmpty)
        #expect(!EquipmentOccupancy.none.conflicts(with: EquipmentOccupancy(slots: .body)))
    }

    /// The WEAP DNAM animation type decides hands until an EQUP decoder exists.
    @Test func twoHandedAnimationTypesTakeBothHands() {
        #expect(EquipmentCatalog.hands(for: .twoHandSword) == .bothHands)
        #expect(EquipmentCatalog.hands(for: .twoHandAxe) == .bothHands)
        #expect(EquipmentCatalog.hands(for: .bow) == .bothHands)
        #expect(EquipmentCatalog.hands(for: .crossbow) == .bothHands)
        #expect(EquipmentCatalog.hands(for: .oneHandSword) == .rightHand)
        #expect(EquipmentCatalog.hands(for: .oneHandDagger) == .rightHand)
        #expect(EquipmentCatalog.hands(for: .staff) == .rightHand)
        // An undocumented animation-type byte decodes to nil and stays
        // equippable as a one-hander rather than becoming unequippable.
        #expect(EquipmentCatalog.hands(for: nil) == .rightHand)
    }
}
