// The session-start pass: each load-order plugin's `.seq` list names the quests
// a new game starts. A listed quest with no runtime state is started for real,
// so its aliases fill and its start-up stage runs. See docs/engine/story-manager.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyQuestsInterface

@MainActor
extension QuestRuntime {
    /// Starts every listed quest that has no runtime state yet. Running it twice
    /// starts nothing the second time.
    public func runSessionStart(
        lists: [PluginQuestList],
        starter: (any QuestStarting)?
    ) -> SessionStartReport {
        var report = SessionStartReport()
        for plugin in lists {
            switch plugin.list {
            case nil:
                report.missingLists.append(plugin.plugin)
            case .failure:
                report.brokenLists.append(plugin.plugin)
            case let .success(list):
                let resolver = FormIDResolver(pluginName: plugin.plugin, masters: plugin.masters)
                for raw in list.quests {
                    guard let resolved = resolver.resolve(raw) else { continue }
                    report.entries.append(sessionStart(
                        storedQuest(resolved, listedBy: plugin.plugin),
                        plugin: plugin.plugin,
                        starter: starter
                    ))
                }
            }
        }
        return report
    }

    /// `HearthFires.seq` writes its own quests with master index 1, which its master
    /// list maps to `Update.esm`. So a FormID that names no stored quest falls back to
    /// the same object ID in the plugin that owns the list (docs/formats/seq.md).
    private func storedQuest(
        _ resolved: ResolvedFormID,
        listedBy plugin: String
    ) -> ResolvedFormID {
        let own = ResolvedFormID(plugin: plugin, objectID: resolved.objectID)
        let isStored = { (id: ResolvedFormID) in
            quests.resolver.localFormID(of: id).flatMap { quests.quest($0) } != nil
        }
        return !isStored(resolved) && isStored(own) ? own : resolved
    }

    private func sessionStart(
        _ resolved: ResolvedFormID,
        plugin: String,
        starter: (any QuestStarting)?
    ) -> SessionStartEntry {
        guard
            let id = quests.resolver.localFormID(of: resolved),
            let quest = quests.quest(id)
        else {
            return SessionStartEntry(
                plugin: plugin, quest: resolved, editorID: nil, outcome: .notInQuestStore
            )
        }
        let outcome: SessionStartOutcome
        if hasRuntimeState(id) {
            outcome = .alreadyHasState
        } else {
            do {
                if let starter {
                    try starter.startQuest(id, event: nil)
                } else {
                    try startQuestWithStartUpStage(id, event: nil)
                }
                outcome = .started
            } catch {
                outcome = .startFailed(String(describing: error))
            }
        }
        return SessionStartEntry(
            plugin: plugin, quest: resolved, editorID: quest.editorID, outcome: outcome
        )
    }
}
