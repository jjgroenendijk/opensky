// The Dialogue readout's sample of the conversation and the live movie.

import Foundation
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionInterface

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

    /// Every considered topic that offered nothing, with why each response lost. A topic
    /// that only a link reaches, or whose quest is not running, says nothing about this
    /// speaker, so it is left out.
    private var rejectionRows: [DialogueRejectionRow] {
        dialogue.selection.rejected
            .filter { offer in
                offer.considered.contains { trace in
                    switch trace.rejection {
                    case .notBranchEntry, .questNotRunning: false
                    default: true
                    }
                }
            }
            .prefix(DialogueControlSnapshot.rejectionLimit)
            .map { offer in
                DialogueRejectionRow(topic: offer.topic, reasons: Self.reasons(offer.considered))
            }
    }

    /// Each distinct phrase once, in first-seen order, with how many responses gave it.
    private static func reasons(_ traces: [DialogueInfoTrace]) -> [String] {
        let phrases = traces.map(reason)
        var seen: [String] = []
        for phrase in phrases where !seen.contains(phrase) {
            seen.append(phrase)
        }
        return seen.map { phrase in
            let count = phrases.count { $0 == phrase }
            return count == 1 ? phrase : "\(phrase) ×\(count)"
        }
    }

    /// The rejection phrase, followed by the conditions the evaluator could not answer.
    private static func reason(_ trace: DialogueInfoTrace) -> String {
        let phrase = trace.rejection.map(DialogueReadout.reason) ?? "offered"
        let unanswered = trace.outcome?.failures ?? []
        guard !unanswered.isEmpty else { return phrase }
        return phrase + " (unanswered: "
            + unanswered.map { String(describing: $0) }.joined(separator: ", ") + ")"
    }
}
