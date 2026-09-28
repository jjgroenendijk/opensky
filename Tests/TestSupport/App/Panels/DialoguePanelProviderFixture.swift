// Recording double and snapshot builder for the dialogue seam (issue #205),
// shared by the panel suite and by the destination-registry satellite.
//
// It lives in its own file for the same reason the journal fixture does: stored
// properties cannot live in an extension, so a fake shared across suites has to
// be one type in one file, and `FakeWorldProviders` already sits near the repo
// file-length limit.

import AppKit
@testable import opensky

/// Builds a `DialogueControlSnapshot` from only the fields a test cares about.
/// The snapshot is immutable by design and its memberwise initializer takes
/// twenty-odd arguments, so a test that wants one non-zero counter would
/// otherwise have to spell out the rest.
nonisolated func makeDialogueSnapshot(
    hasDialogueIndex: Bool = true,
    topicCount: Int = 0,
    infoCount: Int = 0,
    targetName: String? = nil,
    targetKey: ReferenceKey? = nil,
    speaker: String = "",
    isOpen: Bool = false,
    openMenus: [String] = [],
    worldSimPaused: Bool = false,
    state: String = "closed",
    rows: [DialogueTopicRow] = [],
    droppedRowCount: Int = 0,
    selectedIndex: Int = -1,
    subtitle: String? = nil,
    rejections: [DialogueRejectionRow] = [],
    unresolvedConditionCount: Int = 0,
    lastOutcome: String? = nil,
    movieLoaded: Bool = false,
    movieError: String? = nil,
    movieTopicRows: Int = 0,
    movieSelectedIndex: Int? = nil,
    movieSubtitle: String? = nil,
    movieMenuState: Int? = nil,
    movieDiagnostics: DialogueMenuDiagnostics = .none
) -> DialogueControlSnapshot {
    DialogueControlSnapshot(
        hasDialogueIndex: hasDialogueIndex,
        topicCount: topicCount,
        infoCount: infoCount,
        targetName: targetName,
        targetKey: targetKey,
        speaker: speaker,
        isOpen: isOpen,
        openMenus: openMenus,
        worldSimPaused: worldSimPaused,
        state: state,
        rows: rows,
        droppedRowCount: droppedRowCount,
        selectedIndex: selectedIndex,
        subtitle: subtitle,
        rejections: rejections,
        unresolvedConditionCount: unresolvedConditionCount,
        lastOutcome: lastOutcome,
        movieLoaded: movieLoaded,
        movieError: movieError,
        movieTopicRows: movieTopicRows,
        movieSelectedIndex: movieSelectedIndex,
        movieSubtitle: movieSubtitle,
        movieMenuState: movieMenuState,
        movieDiagnostics: movieDiagnostics
    )
}

/// Records what the dialogue section asked for, so a panel-level button click
/// and a registry-level reset are observed through the same fake.
@MainActor
final class FakeDialogueProvider: DialogueControlProviding {
    var snapshot = makeDialogueSnapshot()
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var events: [MenuInputEvent] = []

    var dialogueSnapshot: DialogueControlSnapshot {
        snapshot
    }

    func openDialogue() {
        openCount += 1
    }

    func closeDialogue() {
        closeCount += 1
    }

    func sendDialogueInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}
