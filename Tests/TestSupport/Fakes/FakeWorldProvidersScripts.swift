// `FakeWorldProviders`' ScriptControlProviding forwarding. Both test targets
// share the fake, so its conformances are shared too
// (Tests/TestSupport/AGENTS.md).

import AppKit
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
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

    func setScriptInstructionBudget(_ instructions: Int) {
        scripts.setScriptInstructionBudget(instructions)
    }

    var questAliasQuestEditorIDs: [String] {
        scripts.questAliasQuestEditorIDs
    }

    func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        scripts.questAliasTable(editorID: editorID)
    }
}
