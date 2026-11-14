// The Launch page's place row: the place a new game starts at, picked from the list
// the install gives. The list loads off the main actor; until it has loaded, the row
// shows the saved place and Play stays as it was.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch

extension LaunchPageViewController {
    func configurePlaceControls() {
        PanelComponents.configureButton(
            placeButton, target: self, action: #selector(choosePlace),
            identifier: "LaunchStartPlaceControl"
        )
        placeButton.toolTip = "Choose a named interior or a map marker of the install"
        context.onStartPlacesChange = { [weak self] in self?.refreshPlaces() }
        showPlace()
    }

    /// The name of a start, as the list or the places used last give it.
    func placeName(of start: LaunchStart) -> String {
        if let place = context.startPlaces?.place(for: start) {
            return place.name
        }
        if let recent = LaunchPreferences.savedRecentPlaces().first(where: { $0.start == start }) {
            return recent.name
        }
        switch start {
        case .normal: return "the main menu"
        case let .cell(editorID): return editorID
        case let .exterior(worldspace, x, y): return "\(worldspace) \(x), \(y)"
        case let .marker(worldspace, _, _): return "a map marker in \(worldspace)"
        }
    }

    /// A picked place that the loaded list lacks cannot start a game.
    var missingPlace: LaunchStartProblem? {
        guard
            startForm.kind == .place, let place = startForm.place,
            let list = context.startPlaces, !list.contains(place)
        else { return nil }
        return .placeMissing(placeName(of: place))
    }

    /// The start Play uses, or nil while the fields do not give one.
    var validStart: LaunchStart? {
        guard missingPlace == nil else { return nil }
        return try? startForm.validate().get()
    }

    func refreshPlaces() {
        startOptions.refreshWeathers(from: context.startPlaces)
        showPlace()
        refreshStart()
    }

    func showPlace() {
        let title: String = if let place = startForm.place {
            placeName(of: place)
        } else if context.startPlaces == nil, context.isLoadingStartPlaces {
            "Reading the places"
        } else {
            "Choose a place"
        }
        placeButton.show(
            symbol: "mappin.and.ellipse", title: title,
            colour: missingPlace == nil ? LauncherStyle.text : LauncherStyle.warning
        )
        placeButton.isEnabled = context.startPlaces != nil
    }

    @objc private func choosePlace() {
        guard let list = context.startPlaces else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = StartPlacePickerViewController(
            list: list, recent: LaunchPreferences.savedRecentPlaces()
        ) { [weak self, weak popover] place in
            popover?.close()
            self?.pick(place)
        }
        popover.show(relativeTo: placeButton.bounds, of: placeButton, preferredEdge: .maxY)
    }

    func pick(_ place: StartPlace) {
        startForm.kind = .place
        startForm.place = place.start
        LaunchPreferences.rememberRecent(LaunchRecentPlace(start: place.start, name: place.name))
        showPlace()
        refreshStart()
    }
}
