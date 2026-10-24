// The map movie over the 3D map view. It follows `MapMenuCoordinator`: it starts when
// the map opens, draws each shown marker where the map camera sees it, marks the
// selected one, and hands the movie's button calls back to the map.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyWorldInterface

/// What the map movie needs from the app.
public protocol MapMovieWorld: SWFLayerWorld {
    var gameDateText: String? { get }
    /// Where the map camera sees `point`, 0 to 1 with y down; nil when off screen.
    func mapScreenPoint(_ point: SIMD3<Float>) -> SIMD2<Float>?
}

public final class MapMenuMovieScreen {
    public let map: MapMenuCoordinator
    /// Opens the journal when the movie's journal button is pressed.
    public var onJournal: (() -> Void)?
    private weak var world: (any MapMovieWorld)?
    private let movie: MenuMovieDriver<MapMovieEvent>
    private var isShown = false
    private var sites: [MapMarkerSite] = []

    public init(
        map: MapMenuCoordinator,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any MapMovieWorld)? = nil
    ) {
        self.map = map
        self.world = world
        movie = MenuMovieDriver(movies: movies, hud: hud, label: "map movie") { [weak world] in
            world?.renderer
        }
    }

    public func tick(now: Double) {
        if map.isOpen != isShown {
            if map.isOpen {
                show()
            } else {
                hide()
            }
        }
        guard isShown else { return }
        for event in movie.tick(now: now) where isShown {
            handle(event)
        }
        movie.publish { [self] in refresh($0) }
    }

    private func show() {
        isShown = true
        sites = MapMarkerRules.shown(map.world?.mapMarkerSites() ?? [], around: .zero)
        let markers = sites.map {
            MapMovieMarker(
                name: $0.name, iconType: Int($0.iconType), isUndiscovered: !$0.state.isDiscovered
            )
        }
        let date = world?.gameDateText ?? ""
        movie.start(MenuMovie(
            path: MapMenuMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                MapMenuMovieBridge.prepare(runtime: runtime) { self?.movie.post($0) }
            },
            activate: { runtime in
                MapMenuMovieBridge.activate(date: date, runtime: runtime)
                MapMenuMovieBridge.create(markers, runtime: runtime)
            }
        ), while: { [weak self] in self?.isShown == true })
    }

    private func hide() {
        isShown = false
        sites = []
        movie.stop()
    }

    private func refresh(_ runtime: SWFMovieRuntime) {
        let points = sites.map { world?.mapScreenPoint($0.position) }
        let selected = sites.firstIndex { $0.key == map.selected?.key }
        MapMenuMovieBridge.refresh(points, selected: selected, runtime: runtime)
    }

    func handle(_ event: MapMovieEvent) {
        switch event {
        case let .marker(index):
            guard sites.indices.contains(index), map.select(key: sites[index].key) else { return }
            map.travelToSelected()
        case .toggleLocalMap:
            let next: MapMenuMode = map.mode == .world ? .local : .world
            map.close()
            map.open(next)
        case .playerLocation:
            let mode = map.mode ?? .world
            map.close()
            map.open(mode)
        case .journal:
            map.close()
            onJournal?()
        }
    }
}
