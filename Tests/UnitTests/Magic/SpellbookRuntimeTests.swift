// The spellbook (issue #470, roadmap item 19.7): knowing spells, reading a
// tome, and readying one to a hand through the EQUP slot its ETYP names.
//
// Records are synthetic and built in code (`SpellbookFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct SpellbookRuntimeTests {
    // MARK: - Knowing

    @Test func anActorStartsKnowingNothingAndIsCleanForTheSlot() throws {
        let (spellbook, store) = try SpellbookFixture.runtime()

        #expect(spellbook.state(of: .player).known.isEmpty)
        #expect(store.component(SpellbookState.self, for: .player) == nil)
    }

    @Test func learningAndForgettingASpellAreBothWrittenOnce() throws {
        let (spellbook, store) = try SpellbookFixture.runtime()
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)

        #expect(spellbook.learn(healing, on: .player))
        #expect(spellbook.knows(healing, .player))
        // Learning a spell already known changes nothing.
        #expect(!spellbook.learn(healing, on: .player))

        #expect(spellbook.forget(healing, on: .player))
        #expect(!spellbook.knows(healing, .player))
        #expect(!spellbook.forget(healing, on: .player))
        // The component is dropped entirely once it empties.
        #expect(store.component(SpellbookState.self, for: .player) == nil)
    }

    /// The start-spell set is looked up by the editor IDs UESP names, through
    /// the load order, so a load order carrying neither record grants nothing.
    @Test func startSpellsAreLookedUpByTheEditorIDsUESPNames() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()

        // The fixture carries records named `Flames` and `Healing`, which is
        // exactly the pair `vanillaStartSpellEditorIDs` names.
        #expect(spellbook.grantStartSpells(to: .player) == 2)
        #expect(spellbook.state(of: .player).known == [
            SpellbookFixture.key(SpellbookFixture.Spell.healing),
            SpellbookFixture.key(SpellbookFixture.Spell.flames)
        ].sorted())
        // Granting twice grants nothing the second time.
        #expect(spellbook.grantStartSpells(to: .player) == 0)
    }

    /// An actor's own `SPLO` list arrives through the same grant, which is what
    /// makes a racial power part of the same one write.
    @Test func anActorSpellListIsGrantedBesideTheStartSpells() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let racial = SpellbookFixture.key(SpellbookFixture.Spell.dragonskin)

        #expect(spellbook.grantStartSpells(to: .player, additional: [racial]) == 3)
        #expect(spellbook.knows(racial, .player))
    }

    /// A `SPLO` link this load order cannot answer drops out rather than
    /// becoming a key nothing resolves.
    @Test func anUnresolvableSpellListLinkDropsOut() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()

        let keys = spellbook.resolve(
            [FormID(SpellbookFixture.Spell.healing), FormID(0x00FF_FFFF)],
            fromPlugin: SpellbookFixture.pluginName
        )

        #expect(keys == [SpellbookFixture.key(SpellbookFixture.Spell.healing)])
    }

    /// A key this load order no longer resolves stays known — removing a plugin
    /// must not destroy progress — and simply drops out of the resolved listing.
    @Test func anUnresolvableKnownSpellStaysKnownButDoesNotList() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let ghost = ReferenceKey.plugin(name: "gone.esp", objectID: 0x99)
        spellbook.learn(ghost, on: .player)

        #expect(spellbook.state(of: .player).known == [ghost])
        #expect(spellbook.knownSpells(of: .player).isEmpty)
    }

    // MARK: - Reading a tome

    @Test func readingATomeTeachesItsSpellAndMarksTheBook() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let book = SpellbookFixture.key(SpellbookFixture.Book.healingTome)
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)

        let reading = spellbook.read(book: book, teaching: healing, on: .player)

        #expect(reading.taught)
        #expect(!reading.alreadyRead)
        #expect(spellbook.knows(healing, .player))
        #expect(spellbook.state(of: .player).hasRead(book))
    }

    /// The mark is what stops a second reading teaching again, which is the
    /// whole reason the BOOK "Read" flag exists in save data.
    @Test func readingTheSameTomeTwiceTeachesNothingTheSecondTime() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let book = SpellbookFixture.key(SpellbookFixture.Book.healingTome)
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.read(book: book, teaching: healing, on: .player)
        spellbook.forget(healing, on: .player)

        let second = spellbook.read(book: book, teaching: healing, on: .player)

        #expect(second.alreadyRead)
        #expect(!second.taught)
        #expect(!spellbook.knows(healing, .player))
    }

    @Test func readingABookThatTeachesNothingStillMarksIt() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let novel = SpellbookFixture.key(SpellbookFixture.Book.novel)

        let reading = spellbook.read(book: novel, teaching: nil, on: .player)

        #expect(!reading.taught)
        #expect(spellbook.state(of: .player).hasRead(novel))
        #expect(spellbook.state(of: .player).known.isEmpty)
    }

    // MARK: - Readying

    @Test func aChooseOneSpellGoesIntoWhicheverHandWasAskedFor() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.learn(healing, on: .player)

        let right = try spellbook.equip(healing, in: .right, on: .player)
        #expect(right.hands == .rightHand)
        #expect(spellbook.state(of: .player).rightHand == healing)
        #expect(spellbook.state(of: .player).leftHand == nil)

        let left = try spellbook.equip(healing, in: .left, on: .player)
        #expect(left.hands == .leftHand)
        #expect(spellbook.state(of: .player).leftHand == healing)
    }

    /// A master spell's EQUP names both hands with "use all parents" set, so it
    /// fills both whichever hand the player pressed.
    @Test func aTwoHandedSpellFillsBothHandsFromEitherRequest() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let master = SpellbookFixture.key(SpellbookFixture.Spell.masterHeal)
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.learn(master, on: .player)
        spellbook.learn(healing, on: .player)
        try spellbook.equip(healing, in: .left, on: .player)

        let change = try spellbook.equip(master, in: .right, on: .player)

        #expect(change.hands == .bothHands)
        #expect(change.unequippedSpells == [healing])
        #expect(spellbook.state(of: .player).leftHand == master)
        #expect(spellbook.state(of: .player).rightHand == master)
    }

    /// Voice takes no hand, so there is nothing readying it in one could mean.
    @Test func aSpellWhoseSlotTakesNoHandIsRefused() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let power = SpellbookFixture.key(SpellbookFixture.Spell.dragonskin)
        spellbook.learn(power, on: .player)

        #expect(throws: SpellbookError.notHandEquippable(spell: power)) {
            try spellbook.equip(power, in: .right, on: .player)
        }
    }

    @Test func readyingASpellTheActorDoesNotKnowIsRefused() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)

        #expect(throws: SpellbookError.notKnown(spell: healing, actor: .player)) {
            try spellbook.equip(healing, in: .right, on: .player)
        }
    }

    @Test func unequippingAHandThatHoldsNothingIsNotAnError() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()

        #expect(spellbook.unequip(.right, on: .player) == nil)
    }

    /// Forgetting a spell has to clear the hand holding it in the same write —
    /// the invariant that keeps the readied pair and the known list in one slot.
    @Test func forgettingAReadiedSpellEmptiesItsHand() throws {
        let (spellbook, _) = try SpellbookFixture.runtime()
        let healing = SpellbookFixture.key(SpellbookFixture.Spell.healing)
        spellbook.learn(healing, on: .player)
        try spellbook.equip(healing, in: .right, on: .player)

        spellbook.forget(healing, on: .player)

        #expect(spellbook.state(of: .player).rightHand == nil)
    }
}
