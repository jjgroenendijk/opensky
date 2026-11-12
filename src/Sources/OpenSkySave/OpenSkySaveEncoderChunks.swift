// The order of the component chunks the encoder writes after `RDLT`. Layout:
// docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// Every component that has its own chunk instead of `RDLT`, in file order. Each
    /// writer emits nothing when no entry has its component, so untouched sessions match
    /// older builds' bytes.
    static func writeComponentChunks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveActorChunks.write(entries, into: &writer)
        OpenSkySaveItemAndWorldChunks.write(entries, into: &writer)
    }
}

/// The first component chunks: inventories, quests, actor state, and crime.
nonisolated enum OpenSkySaveActorChunks {
    static func write(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveInventoryWriter.writeInventories(entries, into: &writer)
        OpenSkySaveSpawnsWriter.writeSpawnedReferences(entries, into: &writer)
        OpenSkySaveQuestsWriter.writeQuestStates(entries, into: &writer)
        OpenSkySaveQuestsWriter.writeQuestAliases(entries, into: &writer)
        OpenSkySaveQuestsWriter.writeQuestLocationAliases(entries, into: &writer)
        OpenSkySaveQuestJournalLogsWriter.writeQuestJournalLogs(entries, into: &writer)
        OpenSkySaveActorValuesWriter.writeActorValues(entries, into: &writer)
        OpenSkySaveActorValuesWriter.writeActorValueOverrides(entries, into: &writer)
        OpenSkySaveDeathsWriter.writeDeaths(entries, into: &writer)
        OpenSkySaveCombatWriter.writeCombatStates(entries, into: &writer)
        OpenSkySaveDialogueWriter.writeDialogueStates(entries, into: &writer)
        OpenSkySaveActiveEffectsWriter.writeActiveEffects(entries, into: &writer)
        OpenSkySaveSpellbookWriter.writeSpellbooks(entries, into: &writer)
        OpenSkySaveEnchantedItemsWriter.writeEnchantedItems(entries, into: &writer)
        OpenSkySavePerksWriter.writePerks(entries, into: &writer)
        OpenSkySaveFactionsWriter.writeFactionMemberships(entries, into: &writer)
        OpenSkySaveRelationshipsWriter.writeRelationshipRanks(entries, into: &writer)
        OpenSkySaveRelationshipFavourWriter.writeRelationshipFavour(entries, into: &writer)
        OpenSkySaveProgressWriter.writeProgressChunks(entries, into: &writer)
        OpenSkySaveCrimeWriter.writeCrimeLedgers(entries, into: &writer)
        OpenSkySaveCrimeWriter.writeStolenGoods(entries, into: &writer)
    }
}

/// The later component chunks: item copies, world objects, story, and the player.
nonisolated enum OpenSkySaveItemAndWorldChunks {
    static func write(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveTemperedItems.write(entries, into: &writer)
        OpenSkySaveItemCopies.write(entries, into: &writer)
        OpenSkySaveAlchemyWriter.writeCreatedPotions(entries, into: &writer)
        OpenSkySaveAlchemyWriter.writeIngredientKnowledge(entries, into: &writer)
        OpenSkySaveAlchemyWriter.writeWeaponPoisons(entries, into: &writer)
        OpenSkySaveFavouritesWriter.writeFavourites(entries, into: &writer)
        OpenSkySaveEnchantingWriter.writeEnchanting(entries, into: &writer)
        OpenSkySaveStolenOriginsWriter.writeStolenOrigins(entries, into: &writer)
        OpenSkySaveCrimeViolentGoldWriter.writeViolentCrimeGold(entries, into: &writer)
        OpenSkySaveHarvestWriter.writeHarvests(entries, into: &writer)
        OpenSkySaveLockWriter.writeLocks(entries, into: &writer)
        OpenSkySaveCellResetWriter.writeCellResets(entries, into: &writer)
        OpenSkySaveVendorRestockWriter.writeVendorRestocks(entries, into: &writer)
        OpenSkySaveRelocationWriter.writeRelocations(entries, into: &writer)
        OpenSkySaveMotionTypeWriter.writeMotionTypes(entries, into: &writer)
        OpenSkySaveLeveledRollWriter.writeLeveledRolls(entries, into: &writer)
        OpenSkySaveJournalWriter.writeSceneChunks(entries, into: &writer)
        OpenSkySaveStoryWriter.writeStoryManagerQuests(entries, into: &writer)
        OpenSkySaveStoryWriter.writeDialogueBranches(entries, into: &writer)
        OpenSkySaveHelpMessagesWriter.writeHelpMessages(entries, into: &writer)
        OpenSkySavePlayerRulesWriter.writePlayerRules(entries, into: &writer)
        OpenSkySaveScriptedStateWriter.writeScriptedStates(entries, into: &writer)
        OpenSkySaveJournalWriter.writeJournal(entries, into: &writer)
        OpenSkySaveIdentityAndMapWriter.writeIdentityAndMap(entries, into: &writer)
    }
}
