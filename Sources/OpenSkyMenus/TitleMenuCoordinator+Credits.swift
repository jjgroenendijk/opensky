// The credits screen: `creditsmenu.swf` takes the title menu's layer, scrolls the
// install's credits, and gives the layer back to the title movie when it ends.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension TitleMenuCoordinator {
    func showCredits() {
        guard let files = world?.gameFiles else {
            lastResult = "Credits: no game data"
            try? world?.renderer?.updateSWFRuntime(TitleMenuMovieBridge.returnToMain(runtime:))
            return
        }
        Task {
            let credits = await MenuTextFile.load(CreditsMenuMovieBridge.creditsPath, from: files)
            guard self.isOpen else { return }
            if let credits {
                self.startCredits(credits)
            } else {
                self.lastResult = "Credits: no credits text"
                try? self.world?.renderer?
                    .updateSWFRuntime(TitleMenuMovieBridge.returnToMain(runtime:))
            }
        }
    }

    func startCredits(_ credits: String) {
        creditsShown = true
        creditsClosing = false
        lastResult = "Credits"
        movie.start(MenuMovie(
            path: CreditsMenuMovieBridge.moviePath,
            activate: { [weak self] runtime in
                CreditsMenuMovieBridge.activate(runtime: runtime, credits: credits) {
                    self?.creditsClosing = true
                }
            }
        ), while: { [weak self] in self?.creditsShown == true })
    }

    func closeCredits() {
        guard creditsShown else { return }
        creditsShown = false
        creditsClosing = false
        if isOpen, movieEnabled {
            startMovie()
        }
    }

    /// Escape leaves; the arrow keys scroll in the movie.
    func routeCredits(_ event: MenuInputEvent) {
        if event == .button(.cancel) {
            closeCredits()
        } else if movieLoaded, let renderer = world?.renderer {
            routeMovie(event, renderer: renderer)
        }
    }
}
