// Live app wiring for the dialogue layer (issue #205, roadmap item 17.3): the
// Talk target the crosshair picks up, the use-key event that opens a
// conversation, and the `DialogueRuntime` the conversation is selected from.
//
// AppKit and the renderer stay in this controller satellite; the row model is
// UI/DialogueMenuModel.swift and the movie contract is
// UI/DialogueMenuMovieBridge.swift, both of which build into the CLI target.
// Presentation — the movie lifecycle, the menu stack and the input path — is
// the `GameViewControllerDialogueMenu.swift` satellite beside this one.
//
// A session without game data has no dialogue index, which is the
// `DialogueControlSnapshot.empty` path: the panel then states that dialogue is
// unavailable rather than showing zeros that look like an empty index.
//
// See docs/engine/dialogue-menu.md.

import AppKit
import simd

struct DialogueBridgeState {
    /// The plugin's DIAL/INFO/VTYP index, nil without game data.
    var store: DialogueStore?
    var model = DialogueMenuModel.empty
    /// The selection the open conversation was built from, retained for the
    /// condition-trace readout: it is the evidence for why a topic the player
    /// expected is not listed, and recomputing it twice a second for a readout
    /// would evaluate every condition in the game on every refresh.
    var selection = DialogueSelection.empty
    var isOpen = false
    var movieLoaded = false
    var movieError: String?
    /// Result of the last panel control or activation, kept across ticker
    /// refreshes so the readout does not erase what the user just did.
    var lastOutcome: String?
    /// What the last chosen response led to, held between the line being said
    /// and the list coming back: the follow-up topics and the goodbye flag are
    /// both answers `DialogueRuntime.choose` gives once, and re-asking for them
    /// after the line finished would re-run the result scripts.
    var followUp: DialogueChoice?
    /// Plugin string tables, built once on first use: constructing them walks
    /// the VFS, and the 2 Hz readout must never trigger that.
    var strings: LocalizedStrings?
    var stringsResolved = false
}

extension GameViewController {
    /// Wires the dialogue index and the Talk seams onto a live streamer.
    ///
    /// Two seams, both narrow on purpose. `talkCandidateSource` answers "who is
    /// worth talking to" — a question about death and hostility, which lives
    /// here beside the world-state store rather than inside streaming — and
    /// `onTalkActivation` is the use-key event the menu opens on.
    func wireDialogue(provider: any CellSceneProvider, streamer: CellStreamer) {
        dialogue.store = (provider as? DialogueDataProviding)?.dialogueStore
        streamer.talk.candidateSource = { [weak self] in
            self?.talkCandidates() ?? []
        }
        streamer.talk.activations.add { [weak self] event in
            self?.beginDialogue(with: event.speaker)
        }
    }

    /// Every resident actor the crosshair may pick up as a Talk target.
    ///
    /// Filtered on the two facts that decide whether a conversation is possible
    /// at all, and on nothing else:
    ///
    /// * A dead actor does not talk. `ActorDeathState` is the same latch combat
    ///   targeting reads, so the two cannot disagree about who is alive.
    /// * A hostile actor does not talk. What an actor in combat says belongs to
    ///   DIAL's combat category, and `DialogueRuntime.topics(for:)` offers only
    ///   category 0 — the player's menu — so a hostile actor's menu would be
    ///   the wrong list even when it was not empty. `ActorHostility` is the
    ///   state the combat loop already keeps, so the two cannot disagree about
    ///   who is fighting. A neutral or friendly actor is a target.
    ///
    /// Not filtered on having anything to say: a speaker whose topics all fail
    /// their conditions still opens a menu with an empty list, which is what
    /// makes "why is there nothing here" answerable from the condition trace
    /// rather than from a prompt that silently never appeared.
    func talkCandidates() -> [TalkCandidate] {
        guard let streamer else { return [] }
        return combatActors().compactMap { observation in
            guard
                !observation.isDead,
                combatHostility(of: observation.key) != .hostile,
                let entry = streamer.referenceEntry(key: observation.key),
                let actor = entry.placedActor
            else {
                return nil
            }
            return TalkCandidate(
                key: observation.key,
                reference: entry.formID,
                base: actor.base,
                feet: observation.feet,
                name: dialogueSpeakerName(entry: entry, fallback: observation.name)
            )
        }
    }

    /// What the prompt and the menu call an actor: its resolved FULL name when
    /// the session can resolve one, and the observation's own label otherwise.
    private func dialogueSpeakerName(
        entry: RuntimeReferenceEntry,
        fallback: String
    ) -> String {
        if let name = streamer?.interactionName(reference: entry.formID), !name.isEmpty {
            return name
        }
        return fallback.isEmpty ? entry.key.description : fallback
    }

    /// Plugin string tables, resolved once and cached.
    var dialogueStrings: LocalizedStrings? {
        if dialogue.stringsResolved {
            return dialogue.strings
        }
        dialogue.stringsResolved = true
        dialogue.strings = localizedStringsLoader?()
        return dialogue.strings
    }

    /// The session's dialogue selection layer, or nil without game data.
    ///
    /// Built per call rather than retained because every field of it is a live
    /// read — the quest resolution, the alias table, the condition context and
    /// the clock all move between one conversation and the next — and a
    /// retained copy would answer from whenever it was made. It is a struct
    /// over stores that already exist, so building one costs nothing.
    var dialogueRuntime: DialogueRuntime? {
        guard let store = dialogue.store, let quests = papyrusBridge?.questRuntime else {
            return nil
        }
        return DialogueRuntime(
            store: worldState,
            dialogue: store,
            quests: quests.quests,
            questStates: quests.resolution(),
            context: runtimeStateConditionContext(),
            fragments: papyrusBridge
        )
    }
}

// MARK: - Snapshot

extension GameViewController {
    /// One sample of everything the dialogue readouts show.
    var dialogueSnapshot: DialogueControlSnapshot {
        guard let store = dialogue.store else {
            return .empty
        }
        let target = talkTarget
        let readback = dialogueReadback
        let rows = dialogue.model.topics.prefix(DialogueControlSnapshot.rowLimit).map {
            DialogueTopicRow(
                topic: $0.topic,
                info: $0.info,
                text: $0.text,
                endsConversation: $0.endsConversation
            )
        }
        return DialogueControlSnapshot(
            hasDialogueIndex: true,
            topicCount: store.topicCount,
            infoCount: store.infoCount,
            targetName: target?.interaction.name,
            targetKey: streamer?.talk.speaker,
            speaker: dialogue.model.speaker,
            isOpen: dialogue.isOpen,
            openMenus: menuMode.stack.identifiers.map(\.name),
            worldSimPaused: menuMode.isWorldSimPaused,
            state: dialogue.isOpen ? String(describing: dialogue.model.state) : "closed",
            rows: Array(rows),
            droppedRowCount: max(0, dialogue.model.topics.count - rows.count),
            selectedIndex: dialogue.model.selectedIndex,
            subtitle: dialogue.model.subtitle,
            rejections: dialogueRejectionRows,
            unresolvedConditionCount: dialogue.selection.tally.failureTotal,
            lastOutcome: dialogue.lastOutcome,
            movieLoaded: dialogue.movieLoaded,
            movieError: dialogue.movieError,
            movieTopicRows: readback.rows,
            movieSelectedIndex: readback.selection,
            movieSubtitle: readback.subtitle,
            movieMenuState: readback.menuState,
            movieDiagnostics: readback.diagnostics
        )
    }

    /// What the live movie answers, or nothing when it is not up.
    private var dialogueReadback: DialogueMenuReadback {
        guard dialogue.movieLoaded, let renderer else { return .empty }
        return DialogueMenuMovieBridge.readback(renderer: renderer)
    }

    /// The crosshair target, but only when it is an actor.
    private var talkTarget: InteractionTarget? {
        guard let target = hud.interactionTarget, target.interaction.action == .talk else {
            return nil
        }
        return target
    }

    /// Every considered topic that offered nothing, with the reason each of its
    /// responses lost.
    private var dialogueRejectionRows: [DialogueRejectionRow] {
        dialogue.selection.rejected
            .prefix(DialogueControlSnapshot.rowLimit)
            .map { offer in
                DialogueRejectionRow(
                    topic: offer.topic,
                    reasons: offer.considered.map {
                        $0.rejection.map(DialogueReadout.reason) ?? "offered"
                    }
                )
            }
    }
}
