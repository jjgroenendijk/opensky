// Papyrus bridge for the World > Scripts sidebar panel (issue #278). Sampling
// and formatting live elsewhere — `PapyrusWorldRuntime.scriptsSnapshot` builds
// the value and `ScriptsReadout` words it — so this file is only the seam
// between the panel and the session's VM.
//
// A session without game data has no `papyrus`, which is the
// `ScriptsSnapshot.empty` path: the panel then states that the VM is
// unavailable rather than showing zeros that look like a running VM.

extension GameViewController: ScriptControlProviding {
    /// One sample of the VM, targeted at whatever the crosshair is on.
    ///
    /// The target resolution matches the Runtime State panel's: the HUD names a
    /// FormID, the streamer's resident index turns it into a `ReferenceKey`,
    /// and an unresolved FormID still shows as itself so the readout never goes
    /// blank while the crosshair is plainly on something.
    var scriptsSnapshot: ScriptsSnapshot {
        guard let papyrus else {
            return .empty
        }
        let running = papyrusBridge?.questRuntime?.runningQuests().count ?? 0
        let failures = papyrusBridge?.questAliasFillFailures ?? 0
        guard let target = hud.interactionTarget else {
            return papyrus.scriptsSnapshot(
                runningQuestCount: running, questAliasFillFailures: failures
            )
        }
        let formID = target.interaction.reference
        guard let entry = streamer?.referenceEntry(formID: formID) else {
            return papyrus.scriptsSnapshot(
                targetDescription: formID.description,
                runningQuestCount: running,
                questAliasFillFailures: failures
            )
        }
        return papyrus.scriptsSnapshot(
            target: entry.key,
            runningQuestCount: running,
            questAliasFillFailures: failures
        )
    }

    /// Quests worth inspecting: the ones that declare at least one alias.
    var questAliasQuestEditorIDs: [String] {
        guard let quests = papyrusBridge?.questRuntime?.quests else { return [] }
        return quests.sortedQuests()
            .filter { !$0.aliases.isEmpty }
            .compactMap(\.editorID)
    }

    /// One quest's authored aliases beside what the session filled them with.
    ///
    /// Every alias the record declares is listed, not only the filled ones: an
    /// alias that stayed empty is the interesting case, and dropping it would
    /// make an unimplemented fill type invisible.
    func questAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        guard
            let runtime = papyrusBridge?.questRuntime,
            let quest = runtime.quests.quest(editorID: editorID)
        else {
            return nil
        }
        let filled = (try? runtime.aliasState(of: quest.formID)) ?? .empty
        let state = try? runtime.state(of: quest.formID)
        return ScriptQuestAliasInspection(
            editorID: quest.editorID ?? quest.formID.description,
            formIDText: quest.formID.description,
            isRunning: state?.isRunning ?? false,
            rows: quest.aliases.map { alias in
                ScriptQuestAliasRow(
                    aliasID: alias.id,
                    name: alias.name ?? "",
                    fillType: alias.fillType.name,
                    isOptional: alias.flags.contains(.optional),
                    reference: filled.reference(forAlias: alias.id)?.description
                )
            }
        )
    }

    /// Freezes the VM's own tick. Deliberately not `Renderer.worldSimPaused`:
    /// the world keeps simulating while the scripts on it stand still, which is
    /// what makes the pause useful for inspecting a mid-event VM.
    func setScriptsPaused(_ paused: Bool) {
        papyrus?.isPaused = paused
    }

    /// Runs fixed steps by hand. The runtime clamps the count, so a stray value
    /// from a control cannot stall the frame.
    func stepScripts(ticks: Int) {
        papyrus?.burst(ticks: ticks, gameClock: renderer?.gameClock)
    }
}
