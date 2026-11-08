// Caster checks on the real load order that synthetic suites cannot make: where
// the player's start spells come from, the SPIT shapes of the spells the
// acceptance picture uses, and how many spells the EQUP walk can put in a hand.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct CasterRealDataTests {
    private func stores() throws -> (spells: SpellStore, slots: EquipSlotStore) {
        let root = try #require(RealDataEnvironment.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP"]
        )
        return (
            SpellStore(index: index, effects: MagicEffectStore(index: index)),
            EquipSlotStore(index: index)
        )
    }

    /// The SPIT "PC Start Spell" flag is not how start spells work: vanilla sets
    /// it only on `PCHealRateCombat`. The intro quest's script grants Flames and
    /// Healing, so `SpellStore.vanillaStartSpellEditorIDs` names them.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
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
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aRaceCarriesItsAbilitiesAndPowerInItsSpellList() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
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

    /// Almost every SPIT `spell` resolves to a hand. The exceptions, such as
    /// `WerewolfChangeFX`, are effect shells a script or shout applies, so
    /// `SpellbookError.notHandEquippable` is the right answer for them.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
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
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
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
