// The sub-pages of the system menu: Settings, Controls, Save, Load, Quit, Help, and
// Installed Content.
// Each page has its own model; this routes events to it and carries out what it
// returns. With the movie up, the movie runs each page (docs/engine/system-menu.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
public import OpenSkyMenusInterface
import OpenSkyRendering

extension SystemMenuCoordinator {
    static let quitOptions = ["Main Menu", "Desktop", "Cancel"]

    func showPage(_ page: SystemMenuPage) {
        switch page {
        case .main:
            model.showMain()
        case .settings:
            settingsPage = SettingsPageModel(catalog: settings.store.catalog)
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
        PageRoutes(owner: self).routePage(event)
    }

    /// The movie's request for a category opens it here too.
    /// The movie asked for a category's rows; it shows them with these values.
    @discardableResult
    func openSettingsCategory(_ group: PlayerSettingGroup) -> [SettingsMovieBridge.Row] {
        PageRoutes(owner: self).openSettingsCategory(group)
    }

    /// The movie changed a row itself, after a click, an arrow key, or its Defaults
    /// button. The movie already shows the value.
    func changeSetting(row: Int, to value: Double) {
        guard model.page == .settings, settingsPage.rows.indices.contains(row) else { return }
        settingsPage.select(row: row)
        settings.store.set(settingsPage.rows[row], to: value)
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

    /// A gamepad button pressed while the Controls page waits. True when taken.
    public func captureGamepad(code: UInt32) -> Bool {
        PageRoutes(owner: self).captureGamepad(code: code)
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

    // MARK: - Readout

    var pageSnapshot: SystemMenuPageSnapshot {
        switch model.page {
        case .main:
            return page(rows: model.entries.map(\.title), selected: model.selectedIndex)
        case .settings:
            let shown = movieSettingsRows ?? settings.settingsRows(settingsPage)
            return page(rows: shown.rows, selected: shown.selected)
        case .controls:
            return controlsRowsShown
        case .save, .load:
            return saveLoadRowsShown
        case .quit:
            return quitRowsShown
        case .installedContent, .help:
            if let topic = topicPage?.openTopic {
                return page(rows: [topic.title, topic.text], selected: 0)
            }
            return page(
                rows: topicPage?.topics.map(\.title) ?? [], selected: topicPage?.selectedIndex ?? 0
            )
        }
    }

    /// With the movie, the rows its Controls list draws and its highlight, which the
    /// keys move, so an empty page reads empty.
    private var controlsRowsShown: SystemMenuPageSnapshot {
        guard movieLoaded, let runtime = renderer?.swfRuntime else {
            return page(rows: settings.controlsRows, selected: controlsPage.selectedIndex)
        }
        guard SystemMenuMovieBridge.shownMappingRows(runtime: runtime) > 0 else {
            return page(rows: [], selected: -1)
        }
        return SystemMenuMovieBridge.listRows(
            atPath: SystemMenuMovieBridge.mappingListPath, runtime: runtime
        )
    }

    /// The rows the page shows: with the movie, only the ones it lists.
    public var controls: ControlsPageReadout? {
        PageRoutes(owner: self).controls
    }

    /// The engine rows carry the place and play time; the movie's list has the highlight.
    private var saveLoadRowsShown: SystemMenuPageSnapshot {
        let rows = saveLoadPage?.titles ?? []
        guard let shown = movieList(SystemMenuMovieBridge.saveLoadListPath) else {
            return page(rows: rows, selected: saveLoadPage?.selectedIndex ?? 0)
        }
        guard shown.rows.count == rows.count else { return shown }
        return page(rows: rows, selected: shown.selectedIndex)
    }

    /// The option rows the movie shows, by engine text, and its highlight.
    private var movieSettingsRows: (rows: [String], selected: Int)? {
        guard movieLoaded, let runtime = renderer?.swfRuntime else { return nil }
        guard settingsPage.openGroup != nil else {
            let shown = SystemMenuMovieBridge.listRows(
                atPath: SettingsMovieBridge.categoryListPath, runtime: runtime
            )
            return (SettingsPageModel.categories.map(\.title), shown.selectedIndex)
        }
        guard let shown = SettingsMovieBridge.shownRows(runtime: runtime) else { return nil }
        let all = settings.settingsRows(settingsPage).rows
        let rows = shown.ids.map { all.indices.contains($0) ? all[$0] : "\($0)" }
        return (rows, shown.selected)
    }

    private var quitRowsShown: SystemMenuPageSnapshot {
        movieList(SystemMenuMovieBridge.quitListPath)
            ?? page(rows: quitPage?.options ?? [], selected: quitPage?.selectedIndex ?? 0)
    }

    /// With the movie, its own list and highlight, which the keys move.
    private func movieList(_ path: String) -> SystemMenuPageSnapshot? {
        guard movieLoaded, let runtime = renderer?.swfRuntime else { return nil }
        return SystemMenuMovieBridge.listRows(atPath: path, runtime: runtime)
    }

    private func page(rows: [String], selected: Int) -> SystemMenuPageSnapshot {
        SystemMenuPageSnapshot(rows: rows, selectedIndex: selected)
    }
}

extension SystemMenuCoordinator {
    /// Routes input on the pages and builds the controls readout.
    struct PageRoutes {
        unowned let owner: SystemMenuCoordinator

        func routePage(_ event: MenuInputEvent) {
            let host = owner
            switch host.model.page {
            case .main:
                break
            case .settings:
                routeSettings(event)
            case .controls:
                host.routeControls(host.controlsPage.handle(event))
            case .save, .load:
                if host.saving.route(event, close: { [weak host] in host?.close() }) {
                    host.showPage(.main)
                }
            case .quit:
                routeQuit(event)
            case .installedContent, .help:
                if host.topicPage?.handle(event) == .back {
                    host.topicPage = nil
                    host.showPage(.main)
                }
            }
        }

        @discardableResult
        func openSettingsCategory(_ group: PlayerSettingGroup) -> [SettingsMovieBridge.Row] {
            let settings = owner.settings
            owner.settingsPage.openCategory(group)
            return owner.settingsPage.rows.enumerated().compactMap { index, id in
                guard !SettingsMovieBridge.hiddenRows.contains(id) else { return nil }
                return settings.store.catalog.definition(id).map {
                    SettingsMovieBridge.Row(
                        id: index,
                        definition: $0,
                        value: settings.store.value(id)
                    )
                }
            }
        }

        func captureGamepad(code: UInt32) -> Bool {
            let settings = owner.settings
            guard
                owner.model.isOpen, owner.model.page == .controls, owner.controlsPage.waitingForKey,
                let slot = owner.controlsPage.selectedSlot
            else { return false }
            _ = owner.controlsPage.capture(scanCode: code)
            let result = settings.rebindGamepad(slot.action, to: code)
            owner
                .lastMessage = result == .notRemappable ?
                "\(slot.action.rawValue) cannot be remapped" : nil
            owner.finishMovieRemap(succeeded: result != .notRemappable && result != .unknownKey)
            return true
        }

        func routeSettings(_ event: MenuInputEvent) {
            let settings = owner.settings
            switch owner.settingsPage.handle(event) {
            case let .adjust(id, direction):
                settings.store.step(id, by: direction)
            case .back:
                owner.showPage(.main)
            case nil:
                break
            }
        }

        func routeQuit(_ event: MenuInputEvent) {
            let world = owner.world
            guard var page = owner.quitPage else { return }
            let choice = page.handle(event)
            owner.quitPage = page
            switch choice {
            case .chose(0):
                owner.close()
                world?.quitToMainMenu()
            case .chose(1):
                owner.close()
                world?.quitApplication()
            case .chose, .cancelled:
                owner.quitPage = nil
                owner.showPage(.main)
            case nil:
                break
            }
        }

        var controls: ControlsPageReadout? {
            let settings = owner.settings
            guard owner.model.isOpen, owner.model.page == .controls else { return nil }
            let rows: [ControlsPageReadout.Row] = if owner.movieLoaded {
                owner.movieMappingRows().map {
                    .init(action: $0.text, key: $0.buttonName.isEmpty ? nil : $0.buttonName)
                }
            } else {
                InputBindings.slots.map { slot in
                    .init(
                        action: slot.event,
                        key: settings.bindings.scanCode(for: slot.action).map(settings.keyName)
                    )
                }
            }
            return ControlsPageReadout(waitingForKey: owner.controlsPage.waitingForKey, rows: rows)
        }
    }
}
