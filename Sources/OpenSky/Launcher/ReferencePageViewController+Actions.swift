// The Reference Game page's buttons. `ReferenceGameSession` does the work, and the rules
// sit in `ReferencePageActions` and the `OpenSkyReference` module.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyReference
import OpenSkySave

extension ReferencePageViewController {
    /// Splits the main screen: OpenSky on the left, the Windows game on the right.
    @objc func startBoth() {
        guard let screen = NSScreen.screens.first, let actions = context.actions else { return }
        let titleBar = NSWindow.frameRect(
            forContentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable]
        ).height
        let split = ReferenceSideBySide(
            visible: screen.visibleFrame, screenHeight: screen.frame.height, titleBar: titleBar
        )
        let lowGraphics = lowGraphicsControl.state == .on
        var save: URL?
        if newestSaveControl.state == .on {
            switch ReferencePageActions.newestSave(prefix: ReferenceSettings.prefix()) {
            case let .success(newest): save = newest
            case let .failure(error):
                show(ReferenceNotice(error.message, isProblem: true), in: startLabel)
                return
            }
        }
        guard actions.referenceSession.startGame(at: split.reference, lowGraphics: lowGraphics)
        else { return }
        if lowGraphics {
            GraphicsPageViewController.installPresets()
                .apply(.low, to: GraphicsPageViewController.installSettings())
        }
        actions.placeNextGameWindow(contentRect: split.openSkyContent)
        if let save {
            actions.continueGame(slot: SkyrimSaveImportAdapter.slot(for: save))
            return
        }
        Task { [weak actions] in
            let offer = await OpenSkySaveStore.continueOffer()
            let settings = SettingsStore.shared
            actions?.start(LaunchPlan(
                resumesLatestSave: settings.value(LaunchPreferences.resumesLatestSaveSetting),
                skipsMainMenu: settings.value(LaunchPreferences.skipsMainMenuSetting),
                newestSlot: offer.slot, start: LaunchPreferences.savedStart()
            ))
        }
    }

    @objc func startReferenceOnly() {
        let size = ReferencePageActions.defaultWindowSize
        _ = context.actions?.referenceSession.startGame(
            at: ReferenceWindowFrame(x: 0, y: 0, width: size.0, height: size.1),
            lowGraphics: lowGraphicsControl.state == .on
        )
    }

    @objc func toggleSetting(_ sender: NSButton) {
        guard let key = settingKeys[ObjectIdentifier(sender)] else { return }
        SettingsStore.shared.set(sender.state == .on, for: key)
    }

    @objc func choosePrefix() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select the Wine prefix that holds Windows Steam and the game."
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            ReferenceSettings.storePrefix(url)
            self?.refresh()
        }
    }

    @objc func exportView() {
        guard let actions = context.actions else { return }
        show(actions.referenceSession.exportView(actions.referenceView()), in: viewLabel)
    }

    @objc func captureBoth() {
        guard let actions = context.actions else { return }
        show(actions.referenceSession.capture(
            actions.referenceView(), captureWorld: actions.captureWorld
        ), in: viewLabel)
        refresh()
    }

    @objc func importSave() {
        switch ReferencePageActions.newestSave(prefix: ReferenceSettings.prefix()) {
        case let .success(save):
            context.actions?.continueGame(slot: SkyrimSaveImportAdapter.slot(for: save))
        case let .failure(error):
            show(ReferenceNotice(error.message, isProblem: true), in: viewLabel)
        }
    }
}
