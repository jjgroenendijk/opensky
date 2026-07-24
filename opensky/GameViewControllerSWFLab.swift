// Developer > UI Lab SWF movie bridge (M8.2.5): SWFLabControlProviding over the
// live renderer, built on the 8.2.4 API (SWFMovieLoader.load(path:) ->
// Renderer.setSWFMovie(_:), swfEnabled, lastSWFDrawStats). Satellite of
// GameViewController.swift (500-line file limit); the class holds only the
// factory and the SWFLabState it mutates.
//
// Both the loader and the movie list are resolved once, lazily: enumerating
// `interface\*.swf` walks every mounted archive index, and the 2 Hz panel
// readout must never trigger that walk. A nil renderer (Metal 4 unavailable) or
// a missing install degrades to an empty list and an explanatory readout.

import AppKit

extension GameViewController {
    /// Selector state for the UI Lab SWF section. Value type on the controller
    /// so the bridge below stays a stored-property-free extension.
    struct SWFLabState {
        var loader: SWFMovieLoader?
        var loaderResolved = false
        var moviePaths: [String]?
        var selectedPath: String?
        var loadError: String?
        var tally: SWFMovieTally?
        var unresolvedFontNames: [String] = []
    }
}

extension GameViewController: SWFLabControlProviding {
    var swfMoviePaths: [String] {
        if let cached = swfLab.moviePaths {
            return cached
        }
        let paths = resolveSWFLoader()?.moviePaths() ?? []
        swfLab.moviePaths = paths
        return paths
    }

    var swfLayerEnabled: Bool {
        get { renderer?.swfEnabled ?? true }
        set { renderer?.swfEnabled = newValue }
    }

    func selectSWFMovie(path: String?) {
        swfLab.selectedPath = path
        swfLab.loadError = nil
        swfLab.tally = nil
        swfLab.unresolvedFontNames = []
        guard let path else {
            assignSWFScene(nil)
            return
        }
        guard let loader = resolveSWFLoader() else {
            swfLab.loadError = "No game data located."
            return
        }
        do {
            let scene = try loader.load(path: path)
            swfLab.tally = scene.movie.tally
            swfLab.unresolvedFontNames = scene.unresolvedFontNames
            assignSWFScene(scene)
        } catch {
            // A movie the decoder rejects is reported in the readout; the
            // previously assigned movie is cleared so the frame matches it.
            swfLab.loadError = String(describing: error)
            assignSWFScene(nil)
        }
    }

    var swfLabSnapshot: SWFLabControlSnapshot {
        SWFLabControlSnapshot(
            selectedPath: swfLab.selectedPath,
            layerEnabled: swfLayerEnabled,
            loadError: swfLab.loadError,
            tally: swfLab.tally,
            unresolvedFontNames: swfLab.unresolvedFontNames,
            drawStats: renderer?.lastSWFDrawStats ?? SWFDrawStats(),
            installLoaded: resolveSWFLoader() != nil
        )
    }

    /// Hands the decoded movie to the renderer. `setSWFMovie` builds GPU
    /// resources synchronously and can throw (allocation, pipeline); surface
    /// that in the readout rather than propagating out of a control action.
    private func assignSWFScene(_ scene: SWFMovieScene?) {
        do {
            try renderer?.setSWFMovie(scene)
        } catch {
            swfLab.loadError = "GPU package build failed: \(String(describing: error))"
        }
    }

    private func resolveSWFLoader() -> SWFMovieLoader? {
        if !swfLab.loaderResolved {
            swfLab.loader = swfMovieLoaderFactory?()
            swfLab.loaderResolved = true
        }
        return swfLab.loader
    }
}
