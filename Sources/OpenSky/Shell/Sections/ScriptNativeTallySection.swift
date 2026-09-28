// World > Scripts > Native coverage section (issue #278): how much of the
// Papyrus native surface the session actually exercised, and which missing
// natives cost the most.
//
// Coverage here is observed, not registered: a native nothing has called yet is
// counted nowhere, because the useful question is "what did the scripts this
// install runs ask for", not "how long is the registry". Read-only, so it is
// never overridden.

import AppKit

final class ScriptNativeTallySection: PanelSectionViewController {
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "ScriptNativeTallyStatsLabel"
    )

    override var sectionTitle: String {
        "Native coverage"
    }

    override var sectionIdentifier: String {
        "scriptNativeTally"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "Implemented names counts the distinct natives this session called that "
                    + "never reported unimplemented. An unimplemented native degrades to a "
                    + "logged no-op, so the ranked list is how a user sees what a script "
                    + "could not do."
            ),
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.nativeTallyText(for: provider.scriptsSnapshot)
    }
}
