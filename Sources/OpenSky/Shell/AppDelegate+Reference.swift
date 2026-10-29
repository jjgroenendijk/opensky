// The Game menu's items for the Windows reference game. The launcher hides while the game
// window is open, so these repeat the Reference Game page there; each result shows as the
// game window's subtitle (docs/tools/reference-game.md).

import AppKit
import OpenSkyReference

extension AppDelegate {
    @objc func captureReferencePair(_: Any?) {
        showReference(referenceSession.capture(referenceView(), captureWorld: captureWorld))
    }

    @objc func sendReferenceView(_: Any?) {
        showReference(referenceSession.sendView(referenceView()) { [weak self] notice in
            self?.showReference(notice)
        })
    }

    @objc func followReferenceGame(_: Any?) {
        showReference(referenceSession.follow { [weak self] view in
            self?.followReference(view) ?? false
        })
    }

    private func showReference(_ notice: ReferenceNotice) {
        gameWindow?.subtitle = notice.isProblem ? "[WARNING] \(notice.message)" : notice.message
    }
}
