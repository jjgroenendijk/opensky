// `FakeWorldProviders`' ScriptControlProviding forwarding (issue #278). The fake
// is shared by both test targets, so every conformance it carries has to be too;
// the suite that used to hold this lives on in openskyTests. See
// openskyTestSupport/AGENTS.md.

import AppKit
@testable import opensky
import Testing

/// Forwards the Papyrus seam to the panel tests' recorder rather than
/// duplicating it, so a registry-level reset and a panel-level checkbox click
/// are observed through the same fake. The conformance itself comes from
/// `WorldControlProviders`, which the class already declares; restating it here
/// would be redundant.
extension FakeWorldProviders {
    var scriptsSnapshot: ScriptsSnapshot {
        scripts.scriptsSnapshot
    }

    func setScriptsPaused(_ paused: Bool) {
        scripts.setScriptsPaused(paused)
    }

    func stepScripts(ticks: Int) {
        scripts.stepScripts(ticks: ticks)
    }

    var questAliasQuestEditorIDs: [String] {
        scripts.questAliasQuestEditorIDs
    }

    func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        scripts.questAliasTable(editorID: editorID)
    }
}
