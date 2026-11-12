// The sub-pages of the system menu: Settings, Controls, Save, Load, Quit, Help, and
// Installed Content.
// Each page has its own model; this routes events to it and carries out what it
// returns. The movie mirrors the Settings page (docs/engine/system-menu.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyRendering

extension SystemMenuCoordinator {
    static let quitOptions = ["Main Menu", "Desktop", "Cancel"]

    func showPage(_ page: SystemMenuPage) {
        switch page {
        case .main:
            model.showMain()
            mirrorMovie(SettingsMovieBridge.mainState)
        case .settings:
            settingsPage = SettingsPageModel(catalog: settings.store.catalog)
            mirrorMovie(SettingsMovieBridge.categoryState)
        case .controls:
            controlsPage = ControlsPageModel()
        case .save, .load:
            saving.openPage(saving: page == .save)
        case .quit:
            quitPage = ConfirmationModel(question: "Quit", options: Self.quitOptions)
        case .installedContent, .help:
            showTopicPage(page)
        }
    }

    /// Reads the page's topics and shows it. The movie asks for them when its row is pressed.
    @discardableResult
    func showTopicPage(_ page: SystemMenuPage) -> SystemMenuTopicPageModel? {
        guard model.isOpen, page.isTopicPage else { return nil }
        let topics = topicSource?.systemMenuTopics(page) ?? []
        let built = SystemMenuTopicPageModel(topics: topics)
        topicPage = built
        model.show(page)
        return built
    }

    /// The movie opened a row of the topic list.
    func openTopic(_ index: Int) -> SystemMenuTopic? {
        topicPage?.open(index)
        return topicPage?.openTopic
    }

    func routePage(_ event: MenuInputEvent) {
        switch model.page {
        case .main:
            break
        case .settings:
            routeSettings(event)
        case .controls:
            routeControls(controlsPage.handle(event))
        case .save, .load:
            if saving.route(event, close: { [weak self] in self?.close() }) {
                showPage(.main)
            }
        case .quit:
            routeQuit(event)
        case .installedContent, .help:
            if topicPage?.handle(event) == .back {
                topicPage = nil
                showPage(.main)
            }
        }
    }

    /// The movie's request for a category opens it here too.
    func openSettingsCategory(_ group: PlayerSettingGroup) {
        guard model.page == .settings else { return }
        settingsPage.openCategory(group)
        publishSettingsRows()
    }

    /// A key pressed while the Controls page waits for one. True when taken.
    public func captureKey(scanCode: UInt32) -> Bool {
        guard model.isOpen, model.page == .controls, controlsPage.waitingForKey else {
            return false
        }
        let action = controlsPage.capture(scanCode: scanCode)
        routeControls(action)
        if case let .rebind(rebound, code) = action {
            finishMovieRemap(succeeded: settings.binds(rebound, to: code))
        } else {
            finishMovieRemap(succeeded: true)
        }
        return true
    }

    var isWaitingForKey: Bool {
        model.isOpen && model.page == .controls && controlsPage.waitingForKey
    }

    public func quicksave() {
        saving.quicksave()
    }

    /// Asks before deleting the selected save, as the Delete key does in vanilla.
    func requestDeleteSelectedSave() {
        saveLoadPage?.requestDelete()
    }

    private func routeSettings(_ event: MenuInputEvent) {
        let wasOpen = settingsPage.openGroup
        switch settingsPage.handle(event) {
        case let .adjust(id, direction):
            settings.store.step(id, by: direction)
            publishSettingsRows()
        case .back:
            showPage(.main)
        case nil:
            if wasOpen != settingsPage.openGroup {
                if settingsPage.openGroup == nil {
                    mirrorMovie(SettingsMovieBridge.categoryState)
                } else {
                    publishSettingsRows()
                }
            } else if settingsPage.openGroup != nil {
                publishSettingsRows()
            }
        }
    }

    private func routeControls(_ action: ControlsPageAction?) {
        switch action {
        case let .rebind(action, scanCode):
            lastMessage = settings.rebindMessage(action, to: scanCode)
        case .resetAll:
            settings.resetBindings()
            lastMessage = "Controls reset"
        case .back:
            showPage(.main)
        case nil:
            break
        }
    }

    private func routeQuit(_ event: MenuInputEvent) {
        guard var page = quitPage else { return }
        let choice = page.handle(event)
        quitPage = page
        switch choice {
        case .chose(0):
            close()
            world?.quitToMainMenu()
        case .chose(1):
            close()
            world?.quitApplication()
        case .chose, .cancelled:
            quitPage = nil
            showPage(.main)
        case nil:
            break
        }
    }

    // MARK: - Movie mirror

    private func mirrorMovie(_ state: String) {
        guard movieLoaded, let renderer else { return }
        attempt {
            try renderer.updateSWFRuntime { runtime in
                SettingsMovieBridge.startState(state, runtime: runtime)
            }
        }
    }

    private func publishSettingsRows() {
        guard movieLoaded, let renderer, settingsPage.openGroup != nil else { return }
        let rows = settings.store.movieRows(settingsPage.rows)
        let selected = settingsPage.rowIndex
        attempt {
            try renderer.updateSWFRuntime { runtime in
                SettingsMovieBridge.startState(SettingsMovieBridge.optionsState, runtime: runtime)
                SettingsMovieBridge.publish(rows, selected: selected, runtime: runtime)
            }
        }
    }

    // MARK: - Readout

    var pageSnapshot: SystemMenuPageSnapshot {
        switch model.page {
        case .main:
            return page(rows: model.entries.map(\.title), selected: model.selectedIndex)
        case .settings:
            let shown = settings.settingsRows(settingsPage)
            return page(rows: shown.rows, selected: shown.selected)
        case .controls:
            return page(rows: settings.controlsRows, selected: controlsPage.selectedIndex)
        case .save, .load:
            return page(
                rows: saveLoadPage?.titles ?? [], selected: saveLoadPage?.selectedIndex ?? 0
            )
        case .quit:
            return page(rows: quitPage?.options ?? [], selected: quitPage?.selectedIndex ?? 0)
        case .installedContent, .help:
            if let topic = topicPage?.openTopic {
                return page(rows: [topic.title, topic.text], selected: 0)
            }
            return page(
                rows: topicPage?.topics.map(\.title) ?? [], selected: topicPage?.selectedIndex ?? 0
            )
        }
    }

    private func page(rows: [String], selected: Int) -> SystemMenuPageSnapshot {
        SystemMenuPageSnapshot(rows: rows, selectedIndex: selected)
    }
}
