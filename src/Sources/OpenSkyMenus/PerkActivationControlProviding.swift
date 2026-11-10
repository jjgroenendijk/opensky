// Perk activate choices: what the crosshair target offers, and
// running one without pressing the use key.

import Foundation
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

nonisolated struct PerkActivationSnapshot: Equatable, Sendable {
    /// One choice: its label and how it acts.
    struct Row: Equatable, Sendable {
        let label: String
        let runsImmediately: Bool
        let replacesDefault: Bool

        init(label: String, runsImmediately: Bool, replacesDefault: Bool) {
            self.label = label
            self.runsImmediately = runsImmediately
            self.replacesDefault = replacesDefault
        }

        var title: String {
            let flags = [runsImmediately ? "runs at once" : nil, replacesDefault ? "replaces" : nil]
                .compactMap(\.self)
            return flags.isEmpty ? label : "\(label) (\(flags.joined(separator: ", ")))"
        }
    }

    let target: String?
    let rows: [Row]
    let lastRun: PerkChoiceRun?

    var readout: String {
        [
            "Target: \(target ?? "none")",
            "Choices: \(rows.count)",
            "Last run: \(lastRun?.text ?? "none")"
        ].joined(separator: "\n")
    }
}

extension PerkActivationCoordinator {
    var perkActivationSnapshot: PerkActivationSnapshot {
        guard let target = world?.crosshairTarget else {
            return PerkActivationSnapshot(target: nil, rows: [], lastRun: lastRun)
        }
        let rows = crosshairChoices(target).map { choice in
            PerkActivationSnapshot.Row(
                label: label(of: choice),
                runsImmediately: choice.activation?.runsImmediately == true,
                replacesDefault: choice.activation?.replacesDefault == true
            )
        }
        return PerkActivationSnapshot(
            target: target.interaction.name, rows: rows, lastRun: lastRun
        )
    }

    @discardableResult
    func runPerkChoice(at index: Int) -> Bool {
        guard
            let target = world?.crosshairTarget,
            let key = world?.referenceKey(of: target)
        else { return false }
        let choices = crosshairChoices(target)
        guard choices.indices.contains(index) else { return false }
        run(choices[index], on: key)
        return true
    }

    /// Run-now choices first, then the offered ones, as a press handles them.
    private func crosshairChoices(_ target: InteractionTarget) -> [PerkEntryPointChoice] {
        guard let key = world?.referenceKey(of: target) else { return [] }
        let plan = plan(on: key)
        return plan.immediate + plan.offered
    }
}
