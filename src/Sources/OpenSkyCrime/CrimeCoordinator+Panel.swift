// The crime coordinator's side of the faction panel: the texts the panel shows from
// the coordinator's own state.

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData

extension CrimeCoordinator: CrimeFactionPanelHost {
    /// One line each for the jail stay, the trespass watch, and the open reports.
    var panelStatusText: String {
        var lines: [String] = []
        if let stay = jailStay {
            lines.append("In the \(factionName(stay.faction)) jail: \(stay.sentenceDays) days"
                + (stay.cell == nil ? ", on the way to the cell" : ""))
        }
        if isPlayerTrespassing {
            lines.append("Trespassing: \(trespassWatch.warnings) warning(s)"
                + (trespassWatch.isCharged ? ", charged" : ""))
        }
        if !pendingReports.isEmpty {
            let gold = pendingReports.map { Int($0.gold) }.reduce(0, +)
            lines
                .append(
                    "Open reports: \(pendingReports.count), \(gold) gold a dead witness takes back"
                )
        }
        return lines.joined(separator: "\n")
    }

    var lastCrimeText: String {
        lastCrime.text
    }

    var lastGuardText: String {
        lastGuard.text
    }
}
