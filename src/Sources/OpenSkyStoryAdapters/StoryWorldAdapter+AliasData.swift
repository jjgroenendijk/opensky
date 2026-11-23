// The factions, spells, and items a quest alias gives the reference in it, applied
// through the script bridge and the inventory. See docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyQuests
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldState

extension StoryWorldAdapter {
    func giveAliasData(_ changes: [QuestAliasDataChange]) {
        guard let bridge = game.scripts.bridge else { return }
        for change in changes {
            if change.entered {
                give(change, through: bridge)
            } else {
                take(change, through: bridge)
            }
        }
    }

    private func give(
        _ change: QuestAliasDataChange,
        through bridge: some PapyrusWorldStateBridgePort
    ) {
        for faction in change.factions {
            bridge.addToFaction(change.reference, faction: ReferenceKey(resolved: faction))
        }
        for spell in change.spells {
            bridge.addSpell(ReferenceKey(resolved: spell), to: change.reference)
        }
        for entry in change.items {
            guard let item = bridge.formIDResolver?.localFormID(of: entry.item) else { continue }
            _ = game.inventory.scriptItems.scriptAddItem(
                item, count: entry.count, to: change.reference
            )
        }
    }

    private func take(
        _ change: QuestAliasDataChange,
        through bridge: some PapyrusWorldStateBridgePort
    ) {
        for faction in change.factions {
            bridge.removeFromFaction(change.reference, faction: ReferenceKey(resolved: faction))
        }
        for spell in change.spells {
            bridge.removeSpell(ReferenceKey(resolved: spell), from: change.reference)
        }
    }
}
