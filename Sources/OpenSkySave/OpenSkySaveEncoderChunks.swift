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
        writeInventories(entries, into: &writer)
        writeSpawnedReferences(entries, into: &writer)
        writeQuestStates(entries, into: &writer)
        writeQuestAliases(entries, into: &writer)
        writeQuestLocationAliases(entries, into: &writer)
        writeQuestJournalLogs(entries, into: &writer)
        writeActorValues(entries, into: &writer)
        writeActorValueOverrides(entries, into: &writer)
        writeDeaths(entries, into: &writer)
        writeCombatStates(entries, into: &writer)
        writeDialogueStates(entries, into: &writer)
        writeActiveEffects(entries, into: &writer)
        writeSpellbooks(entries, into: &writer)
        writeEnchantedItems(entries, into: &writer)
        writePerks(entries, into: &writer)
        writeFactionMemberships(entries, into: &writer)
        writeRelationshipRanks(entries, into: &writer)
        writeProgressChunks(entries, into: &writer)
        writeCrimeLedgers(entries, into: &writer)
        writeStolenGoods(entries, into: &writer)
        OpenSkySaveTemperedItems.write(entries, into: &writer)
        OpenSkySaveItemCopies.write(entries, into: &writer)
        writeCreatedPotions(entries, into: &writer)
        writeIngredientKnowledge(entries, into: &writer)
        writeWeaponPoisons(entries, into: &writer)
        writeFavourites(entries, into: &writer)
        writeEnchanting(entries, into: &writer)
        writeViolentCrimeGold(entries, into: &writer)
        writeHarvests(entries, into: &writer)
        writeLocks(entries, into: &writer)
        writeCellResets(entries, into: &writer)
        writeVendorRestocks(entries, into: &writer)
        writeRelocations(entries, into: &writer)
        writeSceneChunks(entries, into: &writer)
        writeStoryManagerQuests(entries, into: &writer)
        writeDialogueBranches(entries, into: &writer)
        writeHelpMessages(entries, into: &writer)
        writeScriptedStates(entries, into: &writer)
        writeJournal(entries, into: &writer)
        writeIdentityAndMap(entries, into: &writer)
    }
}
