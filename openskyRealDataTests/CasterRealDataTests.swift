// Env-gated caster checks against the user's read-only active load order
// (issue #470, roadmap item 19.7). Read-only throughout: nothing here writes to
// the install, and no game bytes leave the machine.
//
// What it pins is exactly the ground the synthetic suites cannot: where the
// player's start spells actually come from (not the SPIT flag that looks like
// it should answer), that the vanilla spells the acceptance picture uses carry
// the SPIT shapes the cast loop was written against, and how many spells the
// EQUP walk can and cannot put in a hand.

import Foundation
@testable import opensky
import Testing

struct CasterRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private func stores() throws -> (spells: SpellStore, slots: EquipSlotStore) {
        let root = try #require(Self.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP"]
        )
        return (
            SpellStore(index: index, effects: MagicEffectStore(index: index)),
            EquipSlotStore(index: index)
        )
    }

    /// The finding that decides where start spells come from, pinned so it
    /// cannot quietly rot.
    ///
    /// The obvious data source would be the SPIT "PC Start Spell" flag. It is
    /// not the mechanism: across the whole vanilla load order that bit is set on
    /// exactly one record, `PCHealRateCombat`, which is not a spell the player
    /// starts with. Vanilla grants Flames and Healing from the intro quest's
    /// Papyrus script instead, so `SpellStore.vanillaStartSpellEditorIDs` names
    /// them and resolves them through the load order.
    @Test(.enabled(if: Self.dataRoot != nil))
    func thePCStartSpellFlagIsNotWhereStartSpellsComeFrom() throws {
        let (spells, _) = try stores()

        let flagged = Set(
            spells.spells.filter(\.isPlayerStartSpell)
                .compactMap(\.editorID).map { $0.lowercased() }
        )
        #expect(!flagged.contains("flames"))
        #expect(!flagged.contains("healing"))
        #expect(flagged.count <= 1)

        // The named set is what the load order actually answers.
        let started = spells.playerStartSpells.compactMap(\.editorID).map { $0.lowercased() }
        #expect(started == ["flames", "healing"])
    }

    /// The other half of the same mechanism: a race's own `SPLO` run, which is
    /// where an actor's abilities and its greater power come from.
    @Test(.enabled(if: Self.dataRoot != nil))
    func aRaceCarriesItsAbilitiesAndPowerInItsSpellList() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(plugins: plugins, recordTypes: ["RACE"])
        var checked = 0

        for indexed in index.definitions(of: "RACE") {
            guard
                let race = try? Race(record: indexed.record, localized: indexed.localized),
                let editorID = race.editorID,
                ["NordRace", "BretonRace", "HighElfRace"].contains(editorID)
            else { continue }
            checked += 1
            // Every playable race authors at least its racial power.
            #expect(!race.spells.isEmpty, "\(editorID) authors no SPLO run")
        }

        // At least one definition each; a load order that overrides a race
        // contributes more than one, which is why this is a floor.
        #expect(checked >= 3)
    }

    /// The two spells the acceptance picture uses, pinned against the SPIT
    /// shapes the cast loop was written against.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theVanillaHealingSpellsCarryTheCastingShapesTheLoopExpects() throws {
        let (spells, _) = try stores()

        let fast = try #require(spells.spell(editorID: "FastHealing"))
        #expect(fast.data?.castingType == .fireAndForget)
        #expect(fast.data?.delivery == .selfTarget)
        #expect((fast.data?.chargeTime ?? 0) > 0)
        #expect(fast.cost.cost > 0)
        // A fire-and-forget heal's entries are instant, which is why a cast
        // moves the health bar and stores no active effect.
        #expect(fast.record.effects.allSatisfy { $0.duration == 0 })

        let healing = try #require(spells.spell(editorID: "Healing"))
        #expect(healing.data?.castingType == .concentration)
        #expect(healing.data?.delivery == .selfTarget)
        #expect(healing.cost.cost > 0)
        #expect(healing.record.effects.allSatisfy { $0.duration == 1 })
    }

    /// Almost every SPIT-type `spell` record resolves to a hand it can be
    /// readied in — and the handful that do not are real, so the number is
    /// measured rather than asserted to be zero.
    ///
    /// The exceptions are effect shells: `WerewolfChangeFX`,
    /// `DLC1VampireChangeFX` and the `DLC2VoiceElementalFury` run are typed as
    /// spells but authored against the Voice slot or none at all, because
    /// nothing equips them — a script or a shout applies them. Readying one is
    /// the documented `SpellbookError.notHandEquippable`, which is the right
    /// answer rather than a gap.
    @Test(.enabled(if: Self.dataRoot != nil))
    func almostEverySpellResolvesToAHandItCanBeReadiedIn() throws {
        let (spells, slots) = try stores()
        var handed = 0
        var handless = 0

        for spell in spells.spells where spell.spellType == .spell {
            let choice = slots.handChoice(
                of: spell.record.equipType,
                fromPlugin: spell.sourcePlugin
            )
            guard let choice, !choice.candidates.isEmpty else {
                handless += 1
                continue
            }
            handed += 1
            // Every one of them offers at least one named hand, which is what
            // `SpellbookRuntime.equip` needs to answer a hand request.
            #expect(choice.occupancy(preferring: .rightHand) != nil)
        }

        #expect(handed > 300)
        // A handful, not a category. If this ever climbed, the ETYP walk would
        // be wrong rather than the data unusual.
        #expect(handless < handed / 20)
    }

    /// A greater power is equipped to the shout button, not to a hand, which is
    /// what makes `SpellbookError.notHandEquippable` the refusal a readied power
    /// gets. Most vanilla powers say so through the Voice slot; a minority
    /// author a hand slot they never use, so this measures the split instead of
    /// claiming one side of it.
    @Test(.enabled(if: Self.dataRoot != nil))
    func mostPowersResolveToNoHandAtAll() throws {
        let (spells, slots) = try stores()
        var handless = 0
        var handed = 0

        for spell in spells.spells
            where spell.spellType == .power || spell.spellType == .lesserPower
        {
            let choice = slots.handChoice(
                of: spell.record.equipType,
                fromPlugin: spell.sourcePlugin
            )
            guard let choice else { continue }
            if choice.candidates.isEmpty {
                handless += 1
            } else {
                handed += 1
            }
        }

        #expect(handless + handed > 20)
        #expect(handless > handed)
    }
}
