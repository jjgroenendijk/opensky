// Dialogue menu presentation (issue #205, roadmap item 17.3): bringing
// `dialoguemenu.swf` up on a Talk activation, driving it, and handing the world
// back. The shape of `GameViewControllerJournal.swift`, with one difference
// that is the whole point of the milestone: this menu is presented under
// `MenuWorldPolicy.leavesWorldRunning`, so the world keeps simulating while the
// player reads the list.
//
// The other difference is the subtitle. The journal draws all its text inside
// its own movie; a spoken line is drawn by the *HUD*, whose
// `SubtitleTextHolder` this publishes into. Both movies cannot be up at once —
// the renderer owns one SWF layer — so the subtitle is written into whichever
// movie is currently loaded, and the dialogue menu's own `SubtitleText` field
// is the one that answers while it is open.
//
// See docs/engine/dialogue-menu.md.

import AppKit
import OSLog

extension GameViewController {
    static let dialogueIdentifier: MenuIdentifier = "Dialogue Menu"

    /// Frames the menu's transitions need to settle after a publish, measured
    /// with `openskycli swf dialogue-menu`: `ShowDialogueList` enters the
    /// movie's own `TRANSITIONING` state and the list holder plays its slide-in
    /// before `eMenuState` reaches `TOPIC_LIST_SHOWN`.
    static let dialogueActivationTicks = 30

    private static let dialogueLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Dialogue"
    )

    /// Opens a conversation with one actor, which is what the use key on a Talk
    /// target does.
    ///
    /// A speaker whose selection offers nothing still opens the menu. That is
    /// deliberate: "this actor had nothing to say" is a result, and the
    /// condition trace beside the list is where the reason lives. Refusing to
    /// open would leave the player pressing a key that appears to do nothing.
    func beginDialogue(with speaker: ReferenceKey) {
        guard !dialogue.isOpen else { return }
        guard let runtime = dialogueRuntime else {
            dialogue.lastOutcome = "no dialogue index loaded"
            return
        }
        let selection = runtime.topics(for: speaker)
        dialogue.selection = selection
        dialogue.model = DialogueMenuModel.build(
            speaker: speaker,
            name: dialogueSpeakerLabel(for: speaker),
            runtime: runtime,
            strings: dialogueStrings
        )
        dialogue.isOpen = true
        recordGreeting(runtime: runtime, speaker: speaker)
        dialogue.lastOutcome = "opened with \(dialogue.model.speaker): "
            + "\(dialogue.model.topics.count) topics, "
            + "\(selection.rejected.count) rejected"
        menuMode.inputConsumer = self
        // The one non-pausing menu in the engine. Voice, facing and lip sync
        // all advance on the world clock, and item 17.4's camera moves while
        // the list is up, so stopping the clock here would stop them.
        menuMode.present(Self.dialogueIdentifier, policy: .leavesWorldRunning)
        startDialogueMovie()
    }

    /// Records the greeting the conversation opened with as said, and runs its
    /// result script.
    ///
    /// A greeting is a delivered response like any other, so it goes through
    /// `DialogueRuntime.choose`: without this a say-once greeting would never
    /// spend itself and the speaker would open with the same line forever. Its
    /// TCLT links are deliberately dropped rather than becoming the topic list —
    /// the greeting is said *over* the offered topics, and taking its links
    /// would replace the list the player is about to read.
    private func recordGreeting(runtime: DialogueRuntime, speaker: ReferenceKey) {
        guard dialogue.model.state == .greeting, let info = dialogue.model.line?.info else {
            return
        }
        do {
            _ = try runtime.choose(info, speaker: speaker)
        } catch {
            dialogue.lastOutcome = "greeting not recorded: \(String(describing: error))"
        }
    }

    /// What the menu calls the speaker: the same resolved name the crosshair
    /// prompt used, so the prompt and the menu header cannot disagree.
    private func dialogueSpeakerLabel(for speaker: ReferenceKey) -> String {
        guard let entry = streamer?.referenceEntry(key: speaker) else {
            return speaker.description
        }
        let name = streamer?.interactionName(reference: entry.formID)
        return name?.isEmpty == false ? (name ?? "") : speaker.description
    }
}

// MARK: - Presentation

extension GameViewController {
    /// Brings the vanilla movie up.
    ///
    /// A missing install, an undecodable movie, or a contract the AS2 subset
    /// cannot satisfy degrades to an explanatory readout — never a thrown error
    /// out of a control action, and never a conversation that cannot be left.
    func startDialogueMovie() {
        guard let renderer, let loader = resolveSWFLoader() else {
            dialogue.movieLoaded = false
            dialogue.movieError = "No game data located."
            return
        }
        do {
            // The renderer owns exactly one SWF layer. Taking it over here is
            // the same handoff the journal and the system menu perform.
            hud.isLoaded = false
            let scene = try loader.load(path: DialogueMenuMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: DialogueMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                dialogue.movieLoaded = false
                dialogue.movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                DialogueMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.closeDialogue()
                }
            }
            for _ in 0 ..< Self.dialogueActivationTicks {
                try renderer.advanceSWFRuntime()
            }
            dialogue.movieLoaded = true
            dialogue.movieError = nil
            publishDialogueModel()
        } catch {
            dialogue.movieLoaded = false
            dialogue.movieError = String(describing: error)
            Self.dialogueLogger.error(
                "[ERROR] dialogue movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the gameplay HUD.
    func stopDialogueMovie() {
        dialogue.movieLoaded = false
        dialogue.movieError = nil
        guard let renderer else { return }
        startHUD(renderer: renderer)
        publishDialogueSubtitle()
    }

    /// Pushes the current model into the movie and repaints.
    func publishDialogueModel() {
        guard dialogue.movieLoaded, let renderer else {
            publishDialogueSubtitle()
            return
        }
        do {
            try renderer.updateSWFRuntime { runtime in
                DialogueMenuMovieBridge.publish(dialogue.model, runtime: runtime)
            }
        } catch {
            dialogue.movieError = String(describing: error)
            Self.dialogueLogger.error(
                "[ERROR] dialogue publish: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Writes the active line into the HUD's subtitle field, or clears it.
    ///
    /// Only reaches the movie when the HUD is the movie that is up, which is
    /// after the conversation has closed. While the dialogue menu is up its own
    /// `SubtitleText` carries the line, and this is what makes sure a line does
    /// not survive the menu it was said in.
    func publishDialogueSubtitle() {
        guard hud.isLoaded, let renderer else { return }
        let subtitle = dialogue.isOpen ? dialogue.model.subtitle : nil
        do {
            try renderer.updateSWFRuntime { runtime in
                HUDMovieBridge.setSubtitleText(subtitle, runtime: runtime)
            }
        } catch {
            Self.dialogueLogger.error(
                "[ERROR] dialogue subtitle: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Routes one menu event into the conversation.
    ///
    /// The engine model is authoritative here, unlike the journal, where the
    /// movie owns the selection and the engine reads it back. The reason is the
    /// measured contract: `TopicList.SetSelectedTopic` does not take a row
    /// index (see `DialogueMenuMovieBridgeLists.select`), so there is no
    /// movie-side cursor to read back that the engine could trust. The movie
    /// still gets the key, so its own focus art and sounds run.
    func routeDialogueInput(_ event: MenuInputEvent) {
        guard dialogue.isOpen else { return }
        if case .button(.cancel) = event {
            closeDialogue()
            return
        }
        if dialogue.movieLoaded, let renderer {
            do {
                _ = try DialogueMenuMovieBridge.send(event, renderer: renderer)
            } catch {
                dialogue.movieError = String(describing: error)
            }
        }
        applyDialogueInput(event)
        publishDialogueModel()
        publishDialogueSubtitle()
    }

    /// The engine's own response to one event.
    private func applyDialogueInput(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): dialogue.model.moveSelection(by: -1)
        case .move(.down): dialogue.model.moveSelection(by: 1)
        case .button(.accept): advanceDialogue()
        default: break
        }
    }

    /// What Enter does, which depends on what the menu is showing.
    ///
    /// While a line is being said it advances to the next run of that response
    /// and then hands the list back, which is also where the subtitle is
    /// cleared. Precise end-of-line timing arrives with item 17.5's playback
    /// clock; until then advancing on input is the stated interim rule.
    private func advanceDialogue() {
        guard dialogue.model.state == .topicList else {
            if !dialogue.model.advanceResponse() {
                finishDialogueResponse()
            }
            return
        }
        chooseDialogueTopic()
    }

    /// Delivers the selected topic's winning response.
    private func chooseDialogueTopic() {
        guard let entry = dialogue.model.selectedTopic else {
            dialogue.lastOutcome = "no topic selected"
            return
        }
        guard let runtime = dialogueRuntime, let speaker = dialogue.model.speakerKey else {
            dialogue.lastOutcome = "no dialogue index loaded"
            return
        }
        guard let info = runtime.dialogue.info(entry.info) else {
            dialogue.lastOutcome = "no loaded plugin declares INFO \(entry.info)"
            return
        }
        do {
            let choice = try runtime.choose(entry.info, speaker: speaker)
            dialogue.selection = choice.next
            dialogue.model.beginResponse(
                info: entry.info,
                runs: DialogueMenuModel.responseRuns(info, strings: dialogueStrings)
            )
            dialogue.followUp = choice
            dialogue.lastOutcome = "said \(entry.info): "
                + "\(choice.next.offers.count) follow-up topics, "
                + "\(choice.dispatchedFragments.count) fragments, "
                + "\(choice.unrunFragmentCount) unrun"
        } catch {
            dialogue.lastOutcome = "choose refused: \(String(describing: error))"
        }
    }

    /// Ends the response being said: goodbye closes the conversation, anything
    /// else hands back whatever the response leads to.
    private func finishDialogueResponse() {
        let follow = dialogue.followUp
        dialogue.followUp = nil
        if follow?.endsConversation == true {
            closeDialogue()
            return
        }
        if let follow, let runtime = dialogueRuntime, !follow.next.offers.isEmpty {
            dialogue.model.setTopics(
                DialogueMenuModel.rows(
                    follow.next, runtime: runtime, strings: dialogueStrings
                )
            )
        } else if
            let runtime = dialogueRuntime,
            let speaker = dialogue.model.speakerKey
        {
            // No links: the speaker is back to whatever they generally offer,
            // re-selected rather than restored from the list the conversation
            // opened with, because choosing a say-once line has just changed it.
            let selection = runtime.topics(for: speaker)
            dialogue.selection = selection
            dialogue.model.setTopics(
                DialogueMenuModel.rows(selection, runtime: runtime, strings: dialogueStrings)
            )
        }
        dialogue.model.showTopicList()
    }
}

// MARK: - Panel seam

extension GameViewController: DialogueControlProviding {
    func openDialogue() {
        guard !dialogue.isOpen else { return }
        guard let speaker = streamer?.talk.speaker else {
            dialogue.lastOutcome = "no actor under the crosshair"
            return
        }
        beginDialogue(with: speaker)
    }

    func closeDialogue() {
        guard dialogue.isOpen else { return }
        dialogue.isOpen = false
        dialogue.followUp = nil
        dialogue.model.showTopicList()
        menuMode.dismiss(Self.dialogueIdentifier)
        if dialogue.movieLoaded {
            stopDialogueMovie()
        } else {
            publishDialogueSubtitle()
        }
    }

    func sendDialogueInput(_ event: MenuInputEvent) {
        routeDialogueInput(event)
    }
}
