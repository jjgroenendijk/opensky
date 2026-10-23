// A menu screen over an `ItemListMenuModel`. The engine owns the selection: arrow keys
// move it and republish, accept acts on the selected row. A click in the movie acts on
// the row the movie's list selected.

import Foundation
import OpenSkyFormatsSWF

public class ItemListMenuScreen: MenuScreen<ItemListMovieEvent> {
    public private(set) var model = ItemListMenuModel(categories: [])
    let moviePath: String
    let title: String
    let hint: String
    var layout: ItemListMovieLayout {
        .inventory
    }

    init(
        identifier: MenuIdentifier,
        movie: ItemListScreenMovie,
        menuMode: MenuModeController,
        layer: (movies: SWFMovieSource?, hud: HUDCoordinator?),
        world: (any MenuScreenWorld)?
    ) {
        moviePath = movie.path
        title = movie.title
        hint = movie.hint
        super.init(
            identifier: identifier, movieReadsKeys: false, menuMode: menuMode,
            layer: layer, world: world
        )
    }

    func presentList() {
        model = ItemListMenuModel(categories: loadCategories())
        present(
            path: moviePath,
            prepare: { [weak self] runtime in
                self?.prepareMovie(runtime) { self?.movie.post($0) }
            },
            activate: { [weak self] runtime in self?.activateMovie(runtime) }
        )
    }

    /// Reads the rows again after an action changed them.
    func reload() {
        model.replace(loadCategories())
        publish()
    }

    override func handleKey(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): model.moveRow(by: -1)
        case .move(.down): model.moveRow(by: 1)
        case .move(.left): model.moveCategory(by: -1)
        case .move(.right): model.moveCategory(by: 1)
        case .button(.accept): chooseSelected(alternate: false)
        case .button(.xButton): chooseSelected(alternate: true)
        case .button(.cancel): close()
        case .button(.yButton), .pointer, .release: return
        }
    }

    override func handle(_ event: ItemListMovieEvent) {
        switch event {
        case .select:
            var row: Int?
            movie.publish { [layout] in
                row = ItemListMenuMovieBridge.selectedRow(layout: layout, runtime: $0)
            }
            if let row {
                model.selectRow(row)
            }
            chooseSelected(alternate: false)
        case .close:
            close()
        }
    }

    private func chooseSelected(alternate: Bool) {
        guard let row = model.selected else {
            lastResult = "No row selected"
            return
        }
        lastResult = choose(row, alternate: alternate)
        reload()
    }

    override func publishMovie(_ runtime: SWFMovieRuntime) {
        ItemListMenuMovieBridge.publish(model, layout: layout, runtime: runtime)
    }

    override var panel: MenuTextPanel {
        let category = model.categories.indices.contains(model.selectedCategory)
            ? model.categories[model.selectedCategory].label : ""
        return MenuTextPanel(
            title: "\(title): \(category)",
            lines: model.rows.map(\.line),
            selection: model.rows.isEmpty ? nil : model.selectedRow,
            hint: hint
        )
    }

    // MARK: - What a list screen sets

    func prepareMovie(
        _ runtime: SWFMovieRuntime,
        post: @escaping @MainActor @Sendable (ItemListMovieEvent) -> Void
    ) {
        ItemListMenuMovieBridge.prepare(runtime: runtime, onEvent: post)
    }

    func activateMovie(_ runtime: SWFMovieRuntime) {
        ItemListMenuMovieBridge.activate(runtime: runtime)
    }

    func loadCategories() -> [ItemListCategory] {
        []
    }

    /// Acts on `row`; the text for the readout. `alternate` is the second action key.
    func choose(_: ItemListRow, alternate _: Bool) -> String {
        "none"
    }
}

/// The movie an item list screen loads, and the title and hint of its text panel.
struct ItemListScreenMovie {
    let path: String
    let title: String
    let hint: String
}
