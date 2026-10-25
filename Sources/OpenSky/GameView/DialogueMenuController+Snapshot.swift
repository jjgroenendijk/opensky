// The Dialogue readout's sample of the conversation and the live movie.

import Foundation
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus

extension DialogueMenuController {
    var snapshot: DialogueControlSnapshot {
        guard dialogue.index != nil else { return .empty }
        let rows = model.topics.prefix(DialogueControlSnapshot.rowLimit).map {
            DialogueTopicRow(text: $0.text)
        }
        return DialogueControlSnapshot(
            isOpen: isOpen,
            openMenus: game.menuMode.stack.identifiers.map(\.name),
            worldSimPaused: game.menuMode.isWorldSimPaused,
            rows: Array(rows),
            selectedIndex: model.selectedIndex,
            subtitle: model.subtitle,
            rejections: rejectionRows,
            unresolvedConditionCount: dialogue.selection.tally.failureTotal
        )
    }

    /// Every considered topic that offered nothing, with why each response lost.
    private var rejectionRows: [DialogueRejectionRow] {
        dialogue.selection.rejected
            .prefix(DialogueControlSnapshot.rowLimit)
            .map { offer in
                DialogueRejectionRow(
                    topic: offer.topic,
                    reasons: offer.considered.map {
                        $0.rejection.map(DialogueReadout.reason) ?? "offered"
                    }
                )
            }
    }
}
