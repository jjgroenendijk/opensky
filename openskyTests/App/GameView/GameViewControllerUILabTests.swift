// Deterministic UI-state coverage for the UI Lab bridge on GameViewController
// (M8.1.4). Exercises the real MenuModeController through the preview actions
// (push/pop/clear naming, pause boundary) and the localized-strings snapshot
// (lazy one-shot install load, degrade without game data) without loading the
// view or touching Metal — the bridge state is renderer-independent.

import AppKit
@testable import opensky
import Testing

struct GameViewControllerUILabTests {
    @Test @MainActor
    func pushPopClearDriveTheRealMenuStack() {
        let controller = GameViewController()
        var snapshot = controller.menuModeSnapshot
        #expect(snapshot == MenuModeControlSnapshot(
            isMenuMode: false, topMenuName: nil, stackDepth: 0, isWorldSimPaused: false
        ))

        controller.pushPreviewMenu()
        snapshot = controller.menuModeSnapshot
        #expect(snapshot == MenuModeControlSnapshot(
            isMenuMode: true, topMenuName: "UILabMenu1", stackDepth: 1, isWorldSimPaused: true
        ))

        controller.pushPreviewMenu()
        snapshot = controller.menuModeSnapshot
        #expect(snapshot.topMenuName == "UILabMenu2")
        #expect(snapshot.stackDepth == 2)

        // Popping an inner menu keeps menu mode (and the pause) active.
        controller.popPreviewMenu()
        snapshot = controller.menuModeSnapshot
        #expect(snapshot.topMenuName == "UILabMenu1")
        #expect(snapshot.isWorldSimPaused)

        controller.clearPreviewMenus()
        snapshot = controller.menuModeSnapshot
        #expect(snapshot == MenuModeControlSnapshot(
            isMenuMode: false, topMenuName: nil, stackDepth: 0, isWorldSimPaused: false
        ))
    }

    @Test @MainActor
    func popNamingStaysDeterministicAfterReuse() {
        let controller = GameViewController()
        controller.pushPreviewMenu()
        controller.pushPreviewMenu()
        controller.popPreviewMenu()
        // Depth-derived names: the next push reuses the freed depth-2 slot.
        controller.pushPreviewMenu()
        #expect(controller.menuModeSnapshot.topMenuName == "UILabMenu2")
        #expect(controller.menuModeSnapshot.stackDepth == 2)
        controller.clearPreviewMenus()
    }

    @Test @MainActor
    func stringsSnapshotDegradesWithoutGameData() {
        let controller = GameViewController()
        let snapshot = controller.localizedLabelsSnapshot
        #expect(snapshot == LocalizedLabelsControlSnapshot(
            sampleShown: false,
            sampleKeyCount: 4,
            language: "english",
            installLoaded: false,
            installFileCount: 0,
            installKeyCount: 0
        ))
    }

    @Test @MainActor
    func stringsSnapshotLoadsInstallCountsOnce() {
        let controller = GameViewController()
        var loads = 0
        controller.localizedLabelsLoader = {
            loads += 1
            return LocalizedLabels(
                language: "english",
                files: [
                    TranslationFile(entries: ["$A": "1", "$B": "2"]),
                    TranslationFile(entries: ["$C": "3"])
                ]
            )
        }
        let snapshot = controller.localizedLabelsSnapshot
        #expect(snapshot.installLoaded)
        #expect(snapshot.installFileCount == 2)
        #expect(snapshot.installKeyCount == 3)
        _ = controller.localizedLabelsSnapshot
        #expect(loads == 1, "install labels loaded \(loads) times, expected once")
    }
}
