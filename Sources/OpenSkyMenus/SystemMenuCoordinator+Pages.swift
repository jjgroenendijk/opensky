// The sub-pages of the system menu: Settings, Controls, Save, Load, and Quit.
// Each page has its own model; this routes events to it and carries out what it
// returns. The movie mirrors the Settings page (docs/engine/system-menu.md).

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

/// The open page and its rows, for the readout and the readout.
nonisolated public struct SystemMenuPageSnapshot: Equatable, Sendable {
    public let rows: [String]
    public let selectedIndex: Int

    public init(
        rows: [String],
        selectedIndex: Int
    ) {
        self.rows = rows
        self.selectedIndex = selectedIndex
    }
}

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
            saveLoadPage = SaveLoadPageModel(
                mode: page == .save ? .save : .load, rows: saves?.saveRows ?? [],
                texts: saveTexts
            )
            refreshSaveRows()
        case .quit:
            quitPage = ConfirmationModel(question: "Quit", options: Self.quitOptions)
        }
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
            routeSaveLoad(event)
        case .quit:
            routeQuit(event)
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
            finishMovieRemap(succeeded: settings.bindings.scanCode(for: rebound) == code)
        } else {
            finishMovieRemap(succeeded: true)
        }
        return true
    }

    public var isWaitingForKey: Bool {
        model.isOpen && model.page == .controls && controlsPage.waitingForKey
    }

    var saveTexts: SaveTexts {
        saves?.saveTexts ?? .vanilla
    }

    public func quicksave() {
        perform(saveTexts.quickSaving, done: saveTexts.quickSaved) {
            _ = try await $0.saveGame(slot: AutosavePolicy.quicksaveSlot)
        }
    }

    /// Asks before deleting the selected save, as the Delete key does in vanilla.
    public func requestDeleteSelectedSave() {
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
            lastMessage = Self.message(for: settings.rebind(action, to: scanCode), action: action)
        case .resetAll:
            settings.resetBindings()
            lastMessage = "Controls reset"
        case .back:
            showPage(.main)
        case nil:
            break
        }
    }

    private func routeSaveLoad(_ event: MenuInputEvent) {
        guard var page = saveLoadPage else { return }
        let action = page.handle(event)
        saveLoadPage = page
        switch action {
        case let .save(slot):
            perform("Saving", done: saveTexts.saved) { _ = try await $0.saveGame(slot: slot) }
        case let .load(slot):
            perform(saveTexts.loading, done: "Loaded", closes: true) {
                try await $0.loadGame(slot: slot)
            }
        case let .delete(slot):
            perform("Deleting", done: saveTexts.deleted) { try await $0.deleteSave(slot: slot) }
        case .exportSkyrim:
            perform("Exporting", done: "Exported") { try await $0.exportSkyrimSave() }
        case .back:
            saveLoadPage = nil
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

    private func refreshSaveRows() {
        guard let saves else { return }
        Task {
            let rows = await saves.refreshSaveRows()
            self.saveLoadPage?.replaceRows(rows)
        }
    }

    /// Shows `running` until the file work ends. A finished load closes the menu.
    func perform(
        _ running: String, done: String, closes: Bool = false,
        _ body: @escaping @MainActor (SaveGameService) async throws -> Void
    ) {
        guard let saves else {
            lastMessage = "Saving unavailable"
            return
        }
        guard saveWork == nil else { return }
        lastMessage = running
        saveWork = Task {
            do {
                try await body(saves)
                self.lastMessage = done
                if closes {
                    self.close()
                }
            } catch {
                self.lastMessage = "\(self.saveTexts.saveFailed) \(error)"
            }
            self.saveWork = nil
            self.refreshSaveRows()
        }
    }

    private static func message(for result: InputRebindResult, action: GameInputAction) -> String {
        switch result {
        case .bound: "Bound \(action.rawValue)"
        case let .swapped(other): "Bound \(action.rawValue), swapped with \(other.rawValue)"
        case .notRemappable: "\(action.rawValue) cannot be remapped"
        case .unknownKey: "That key cannot be bound"
        }
    }

    // MARK: - Movie mirror

    private func mirrorMovie(_ state: String) {
        guard movieLoaded, let renderer else { return }
        try? renderer.updateSWFRuntime { runtime in
            SettingsMovieBridge.startState(state, runtime: runtime)
        }
    }

    private func publishSettingsRows() {
        guard movieLoaded, let renderer, settingsPage.openGroup != nil else { return }
        let store = settings.store
        let rows = settingsPage.rows.compactMap { id in
            store.catalog.definition(id).map { (definition: $0, value: store.value(id)) }
        }
        let selected = settingsPage.rowIndex
        try? renderer.updateSWFRuntime { runtime in
            SettingsMovieBridge.startState(SettingsMovieBridge.optionsState, runtime: runtime)
            SettingsMovieBridge.publish(rows, selected: selected, runtime: runtime)
        }
    }

    // MARK: - Readout

    var pageSnapshot: SystemMenuPageSnapshot {
        switch model.page {
        case .main:
            return page(rows: model.entries.map(\.title), selected: model.selectedIndex)
        case .settings:
            return settingsSnapshot
        case .controls:
            let bindings = settings.bindings
            let rows = InputBindings.slots.map { slot in
                let key = bindings.scanCode(for: slot.action)
                    .map { self.settings.keyName($0) }
                    ?? "none"
                return "\(slot.event): \(key)"
            } + [ControlsPageModel.resetTitle]
            return page(rows: rows, selected: controlsPage.selectedIndex)
        case .save, .load:
            return page(
                rows: saveLoadPage?.titles ?? [], selected: saveLoadPage?.selectedIndex ?? 0
            )
        case .quit:
            return page(rows: quitPage?.options ?? [], selected: quitPage?.selectedIndex ?? 0)
        }
    }

    private var settingsSnapshot: SystemMenuPageSnapshot {
        let store = settings.store
        guard settingsPage.openGroup != nil else {
            return page(
                rows: SettingsPageModel.categories.map(\.title),
                selected: SettingsPageModel.categories
                    .firstIndex(of: settingsPage.selectedCategory) ?? 0
            )
        }
        let rows = settingsPage.rows.map { id in
            let definition = store.catalog.definition(id)
            let value = Self.valueText(store.value(id), definition: definition)
            return "\(definition?.title ?? id.rawValue): \(value)"
        }
        return page(rows: rows, selected: settingsPage.rowIndex)
    }

    static func valueText(_ value: Double, definition: PlayerSettingDefinition?) -> String {
        switch definition?.kind {
        case .toggle: value >= 0.5 ? "On" : "Off"
        case let .choice(options):
            options.indices.contains(Int(value)) ? options[Int(value)] : "\(Int(value))"
        default: String(format: "%.2f", value)
        }
    }

    private func page(rows: [String], selected: Int) -> SystemMenuPageSnapshot {
        SystemMenuPageSnapshot(rows: rows, selectedIndex: selected)
    }
}
