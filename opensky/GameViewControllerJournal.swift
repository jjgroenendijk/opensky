// Journal bridge for the World > Quests & Journal sidebar and the world-mode
// journal key (issue #184). AppKit and the renderer stay in this controller
// satellite; the row model is UI/JournalMenuModel.swift and the movie contract
// is UI/QuestJournalMovieBridge.swift, both of which build into the CLI target.
//
// The journal shares one movie with the system menu — `quest_journal.swf` is
// both — so this file reuses `SystemMenuMovieBridge` for the lifecycle calls
// and the input path, and only adds the Quests-page half. That is also why the
// two cannot be open at once: they are the same movie on the renderer's single
// SWF layer, and each pushes its own menu-stack identifier.
//
// A session without game data has no quest runtime, which is the
// `JournalControlSnapshot.empty` path: the panel then states that quests are
// unavailable rather than showing zeros that look like an empty index.
//
// See docs/engine/journal.md.

import AppKit
import OSLog

struct JournalRuntimeState {
    var model = JournalMenuModel.empty
    var isOpen = false
    var movieLoaded = false
    var movieError: String?
    /// Quest the dev controls act on, as typed into the panel.
    var editorID = ""
    /// Result of the last dev control, kept across ticker refreshes so the
    /// readout does not erase what the user just did.
    var lastOutcome: String?
    /// Plugin string tables, built once on first use: constructing them walks
    /// the VFS, and the 2 Hz readout must never trigger that.
    var strings: LocalizedStrings?
    var stringsResolved = false
}

extension GameViewController {
    static let journalIdentifier: MenuIdentifier = "Journal"

    /// Frames the journal's top-level fade needs to settle after `ShowMenu`,
    /// the same count the system menu measured against the install.
    static var journalActivationTicks: Int {
        systemMenuActivationTicks
    }

    private static let journalLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Journal"
    )

    /// The session's quest layer, or nil without game data.
    var journalQuestRuntime: QuestRuntime? {
        papyrusBridge?.questRuntime
    }

    /// Plugin string tables, resolved once and cached.
    var journalStrings: LocalizedStrings? {
        if journal.stringsResolved {
            return journal.strings
        }
        journal.stringsResolved = true
        journal.strings = localizedStringsLoader?()
        return journal.strings
    }

    /// Rebuilds the page model from live quest state, keeping the current
    /// selection and list.
    func refreshJournalModel() {
        guard let runtime = journalQuestRuntime else {
            journal.model = .empty
            return
        }
        journal.model = JournalMenuModel.build(
            runtime: runtime,
            strings: journalStrings,
            aliases: journalAliasNaming(runtime: runtime),
            showsCompleted: journal.model.showsCompleted,
            selectedIndex: max(journal.model.selectedIndex, 0)
        )
        selectJournalRow(forEditorID: journal.editorID)
    }

    /// Points the page at the quest the panel names, when it is listed. A quest
    /// that is not running is not on the page, and the selection stays put
    /// rather than jumping to an unrelated row.
    private func selectJournalRow(forEditorID editorID: String) {
        let wanted = editorID.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return }
        guard
            let row = journal.model.entries.firstIndex(where: {
                $0.editorID.lowercased() == wanted
            })
        else {
            return
        }
        journal.model.select(row)
    }

    /// Alias substitution for journal text: names an alias by whatever the
    /// session filled it with, and only while that reference is in a loaded
    /// cell. A fill outside the loaded area leaves the tag as written, which
    /// the page shows verbatim rather than silently dropping.
    private func journalAliasNaming(runtime: QuestRuntime) -> QuestAliasNaming {
        let aliases = runtime.aliasResolution()
        return QuestAliasNaming { [weak self] quest, aliasID in
            guard
                let key = aliases.reference(alias: aliasID, in: quest),
                let entry = self?.streamer?.referenceEntry(key: key),
                let name = self?.streamer?.interactionName(reference: entry.formID),
                !name.isEmpty
            else {
                return nil
            }
            return name
        }
    }
}

// MARK: - Presentation

extension GameViewController {
    /// Brings the vanilla movie up on its Quests page.
    ///
    /// A missing install, an undecodable movie, or a contract the AS2 subset
    /// cannot satisfy degrades to an explanatory readout — never a thrown error
    /// out of a control action.
    func startJournalMovie() {
        guard let renderer, let loader = resolveSWFLoader() else {
            journal.movieLoaded = false
            journal.movieError = "No game data located."
            return
        }
        do {
            // The renderer owns exactly one SWF layer. Taking it over here is
            // the same handoff the system menu performs.
            hud.isLoaded = false
            let scene = try loader.load(path: QuestJournalMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: SystemMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                journal.movieLoaded = false
                journal.movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                // The lifecycle calls belong to the movie as a whole, so the
                // system-menu bridge makes them; only the page switch is ours.
                SystemMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.closeJournal()
                }
                QuestJournalMovieBridge.activate(runtime: runtime)
            }
            for _ in 0 ..< Self.journalActivationTicks {
                try renderer.advanceSWFRuntime()
            }
            journal.movieLoaded = true
            journal.movieError = nil
            publishJournalModel()
        } catch {
            journal.movieLoaded = false
            journal.movieError = String(describing: error)
            Self.journalLogger.error(
                "[ERROR] journal movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the gameplay HUD.
    func stopJournalMovie() {
        journal.movieLoaded = false
        journal.movieError = nil
        guard let renderer else { return }
        startHUD(renderer: renderer)
    }

    /// Pushes the current model into the movie and repaints.
    func publishJournalModel() {
        guard journal.movieLoaded, let renderer else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                QuestJournalMovieBridge.publish(journal.model, runtime: runtime)
            }
        } catch {
            journal.movieError = String(describing: error)
            Self.journalLogger.error(
                "[ERROR] journal publish: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Routes one menu event into the journal.
    ///
    /// The movie gets it first, through the same batched renderer seam the
    /// system menu uses, so the tab strip across the top keeps switching to
    /// Stats and System. Whatever the movie did to the title list's selection
    /// is then read back into the model and republished, which is what makes
    /// the objectives and the description follow the highlighted quest.
    func routeJournalInput(_ event: MenuInputEvent) {
        guard journal.isOpen else { return }
        if case .button(.cancel) = event {
            closeJournal()
            return
        }
        guard journal.movieLoaded, let renderer else {
            applyJournalFallbackInput(event)
            return
        }
        do {
            _ = try SystemMenuMovieBridge.send(event, renderer: renderer)
            let selected = renderer.swfRuntime.flatMap { runtime in
                QuestJournalMovieBridge.selectedIndex(
                    runtime: runtime, atPath: QuestJournalMovieBridge.titleListPath
                )
            }
            if let selected {
                journal.model.select(selected)
            } else {
                applyJournalFallbackInput(event)
            }
            publishJournalModel()
        } catch {
            journal.movieError = String(describing: error)
            Self.journalLogger.error(
                "[ERROR] journal input: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Selection moves with no movie loaded, so the panel's Up/Down still mean
    /// something on a session with no install.
    private func applyJournalFallbackInput(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): journal.model.moveSelection(by: -1)
        case .move(.down): journal.model.moveSelection(by: 1)
        default: break
        }
    }
}

// MARK: - Panel seam

extension GameViewController: JournalControlProviding {
    var journalQuestEditorID: String {
        get { journal.editorID }
        set {
            guard newValue != journal.editorID else { return }
            journal.editorID = newValue
            refreshJournalModel()
            publishJournalModel()
        }
    }

    var journalQuestEditorIDs: [String] {
        guard let quests = journalQuestRuntime?.quests else { return [] }
        return quests.journalQuests().compactMap(\.editorID)
    }

    func openJournal() {
        guard !journal.isOpen else { return }
        journal.isOpen = true
        refreshJournalModel()
        menuMode.inputConsumer = self
        menuMode.present(Self.journalIdentifier)
        startJournalMovie()
    }

    func closeJournal() {
        guard journal.isOpen else { return }
        journal.isOpen = false
        menuMode.dismiss(Self.journalIdentifier)
        if journal.movieLoaded {
            stopJournalMovie()
        }
    }

    func sendJournalInput(_ event: MenuInputEvent) {
        routeJournalInput(event)
    }

    func setJournalShowsCompleted(_ flag: Bool) {
        journal.model.setShowsCompleted(flag)
        publishJournalModel()
    }

    func startSelectedQuest() {
        applyQuestChange("start") { runtime, formID in
            let state = try runtime.startQuest(formID)
            return "started, stage \(state.currentStage.map(String.init) ?? "none")"
        }
    }

    func stopSelectedQuest() {
        applyQuestChange("stop") { runtime, formID in
            _ = try runtime.stopQuest(formID)
            return "stopped, aliases cleared"
        }
    }

    func setSelectedQuestStage(_ index: Int) {
        guard let stage = UInt16(exactly: index), index >= 0 else {
            journal.lastOutcome = "stage \(index) is not a stage index"
            return
        }
        applyQuestChange("set stage \(stage)") { runtime, formID in
            let state = try runtime.setStage(stage, on: formID)
            return "stage \(stage) reached, current \(state.stageValue)"
        }
    }

    func setSelectedQuestObjective(_ index: Int, displayed: Bool) {
        guard let objective = UInt16(exactly: index), index >= 0 else {
            journal.lastOutcome = "objective \(index) is not an objective index"
            return
        }
        applyQuestChange("objective \(objective)") { runtime, formID in
            _ = try runtime.setObjectiveDisplayed(objective, displayed, on: formID)
            return "objective \(objective) \(displayed ? "displayed" : "hidden")"
        }
    }

    func journalAliasTable(editorID: String) -> ScriptQuestAliasInspection? {
        questAliasTable(editorID: editorID)
    }

    /// Runs one quest mutation, records what it did or why it refused, and
    /// republishes. Every `QuestError` is a stated outcome rather than a thrown
    /// error out of a control action.
    private func applyQuestChange(
        _ label: String,
        _ change: (QuestRuntime, FormID) throws -> String
    ) {
        guard let runtime = journalQuestRuntime else {
            journal.lastOutcome = "\(label): no quest index loaded"
            return
        }
        let editorID = journal.editorID.trimmingCharacters(in: .whitespaces)
        guard let quest = runtime.quests.quest(editorID: editorID) else {
            journal.lastOutcome = editorID.isEmpty
                ? "\(label): no quest selected"
                : "\(label): no loaded plugin defines \(editorID)"
            return
        }
        do {
            journal.lastOutcome = try "\(quest.editorID ?? editorID): "
                + change(runtime, quest.formID)
        } catch {
            journal.lastOutcome = "\(label) refused: \(String(describing: error))"
        }
        refreshJournalModel()
        publishJournalModel()
    }
}
