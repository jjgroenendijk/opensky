// The Launch page's start menu: the main menu, or a settlement of the install, under a
// heading for its worldspace. The list loads off the main actor; until it has loaded, a
// saved place start shows "Reading the places" and Play waits.

import AppKit
import OpenSkyLaunch

extension LaunchPageViewController {
    static let mainMenuTitle = "Main menu"
    static let readingTitle = "Reading the places"

    func configureStartMenu() {
        PanelComponents.configurePopUp(
            startPopUp, target: self, action: #selector(startChanged),
            identifier: "LaunchStartControl"
        )
        startPopUp.toolTip = "Where a new game starts: the main menu, or a town of the install"
        context.onStartPlacesChange = { [weak self] in self?.refreshPlaces() }
        showStartMenu()
    }

    /// The name of a start, as the list gives it.
    func placeName(of start: LaunchStart) -> String {
        if let place = context.startPlaces?.place(for: start) {
            return place.name
        }
        switch start {
        case .normal: return "the main menu"
        case let .cell(editorID): return editorID
        case let .exterior(worldspace, x, y): return "\(worldspace) \(x), \(y)"
        case let .marker(worldspace, _, _): return "a map marker in \(worldspace)"
        }
    }

    /// The start Play uses, or nil while the list it names has not loaded.
    var validStart: LaunchStart? {
        start == .normal || context.startPlaces != nil ? start : nil
    }

    func refreshPlaces() {
        startOptions.refreshWeathers(from: context.startPlaces)
        showStartMenu()
        refreshStart()
    }

    /// A saved start the loaded settlements lack falls back to the main menu.
    func showStartMenu() {
        let settlements = context.startPlaces?.settlements
        if let settlements, !settlements.contains(start) {
            start = .normal
            LaunchPreferences.remember(start)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item(Self.mainMenuTitle, for: .normal))
        if let settlements {
            for group in settlements.groups {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: group.title))
                for place in group.places {
                    let entry = item(place.name, for: place.start)
                    entry.indentationLevel = 1
                    menu.addItem(entry)
                }
            }
        } else if start != .normal {
            let reading = item(Self.readingTitle, for: start)
            reading.isEnabled = false
            menu.addItem(reading)
        }
        startPopUp.menu = menu
        startPopUp.select(menu.items.first { $0.representedObject as? String == start.storedValue })
    }

    private func item(_ title: String, for start: LaunchStart) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = start.storedValue
        return item
    }

    @objc private func startChanged() {
        guard
            let value = startPopUp.selectedItem?.representedObject as? String,
            let picked = LaunchStart(storedValue: value)
        else { return }
        start = picked
        LaunchPreferences.remember(start)
        refreshStart()
    }
}
