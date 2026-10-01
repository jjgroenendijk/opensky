// The UI Lab menu-mode preview over the real MenuModeController, and the
// localized-strings counts. No world is attached, so there is no renderer.

@testable import OpenSkyFormatsCore
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct UILabCoordinatorTests {
    @Test @MainActor
    func pushPopClearDriveTheRealMenuStack() {
        let lab = UILabCoordinator(menuMode: MenuModeController())
        var snapshot = lab.menuModeSnapshot
        #expect(snapshot == MenuModeControlSnapshot(
            isMenuMode: false, topMenuName: nil, stackDepth: 0, isWorldSimPaused: false
        ))

        lab.pushPreviewMenu()
        snapshot = lab.menuModeSnapshot
        #expect(snapshot == MenuModeControlSnapshot(
            isMenuMode: true, topMenuName: "UILabMenu1", stackDepth: 1, isWorldSimPaused: true
        ))

        lab.pushPreviewMenu()
        snapshot = lab.menuModeSnapshot
        #expect(snapshot.topMenuName == "UILabMenu2")
        #expect(snapshot.stackDepth == 2)

        // Popping an inner menu keeps menu mode (and the pause) active.
        lab.popPreviewMenu()
        snapshot = lab.menuModeSnapshot
        #expect(snapshot.topMenuName == "UILabMenu1")
        #expect(snapshot.isWorldSimPaused)

        lab.clearPreviewMenus()
        snapshot = lab.menuModeSnapshot
        #expect(snapshot == MenuModeControlSnapshot(
            isMenuMode: false, topMenuName: nil, stackDepth: 0, isWorldSimPaused: false
        ))
    }

    @Test @MainActor
    func popNamingStaysDeterministicAfterReuse() {
        let lab = UILabCoordinator(menuMode: MenuModeController())
        lab.pushPreviewMenu()
        lab.pushPreviewMenu()
        lab.popPreviewMenu()
        // Depth-derived names: the next push reuses the freed depth-2 slot.
        lab.pushPreviewMenu()
        #expect(lab.menuModeSnapshot.topMenuName == "UILabMenu2")
        #expect(lab.menuModeSnapshot.stackDepth == 2)
        lab.clearPreviewMenus()
    }

    @Test @MainActor
    func stringsSnapshotDegradesWithoutGameData() {
        let lab = UILabCoordinator(menuMode: MenuModeController())
        let snapshot = lab.localizedLabelsSnapshot
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
        let lab = UILabCoordinator(menuMode: MenuModeController())
        var loads = 0
        lab.localizedLabelsLoader = {
            loads += 1
            return LocalizedLabels(
                language: "english",
                files: [
                    TranslationFile(entries: ["$A": "1", "$B": "2"]),
                    TranslationFile(entries: ["$C": "3"])
                ]
            )
        }
        let snapshot = lab.localizedLabelsSnapshot
        #expect(snapshot.installLoaded)
        #expect(snapshot.installFileCount == 2)
        #expect(snapshot.installKeyCount == 3)
        _ = lab.localizedLabelsSnapshot
        #expect(loads == 1, "install labels loaded \(loads) times, expected once")
    }
}
