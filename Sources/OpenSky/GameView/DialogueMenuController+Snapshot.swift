// The Dialogue panel's sample of the conversation and the live movie.

import Foundation
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface

extension DialogueMenuController {
    var snapshot: DialogueControlSnapshot {
        guard let index = dialogue.index else { return .empty }
        let readback = movieLoaded
            ? game.renderer.map(DialogueMenuMovieBridge.readback(renderer:)) ?? .empty
            : .empty
        let rows = model.topics.prefix(DialogueControlSnapshot.rowLimit).map {
            DialogueTopicRow(info: $0.info, text: $0.text, endsConversation: $0.endsConversation)
        }
        return DialogueControlSnapshot(
            hasDialogueIndex: true,
            topicCount: index.topicCount,
            infoCount: index.infoCount,
            targetName: talkTarget?.interaction.name,
            targetKey: game.streamer?.talk.speaker,
            speaker: model.speaker,
            isOpen: isOpen,
            openMenus: game.menuMode.stack.identifiers.map(\.name),
            worldSimPaused: game.menuMode.isWorldSimPaused,
            state: isOpen ? String(describing: model.state) : "closed",
            rows: Array(rows),
            droppedRowCount: max(0, model.topics.count - rows.count),
            selectedIndex: model.selectedIndex,
            subtitle: model.subtitle,
            rejections: rejectionRows,
            unresolvedConditionCount: dialogue.selection.tally.failureTotal,
            lastOutcome: dialogue.lastOutcome,
            movieLoaded: movieLoaded,
            movieError: movieError,
            movieTopicRows: readback.rows,
            movieSelectedIndex: readback.selection,
            movieSubtitle: readback.subtitle,
            movieMenuState: readback.menuState,
            movieDiagnostics: readback.diagnostics
        )
    }

    private var talkTarget: InteractionTarget? {
        guard let target = game.hud.interactionTarget, target.interaction.action == .talk else {
            return nil
        }
        return target
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
