// The HUD's big quest and shout notices, and notice lines that play a sound.
// See docs/engine/journal.md#hud-notices.

import OpenSkyFormatsSWF
import OpenSkyRendering

extension HUDCoordinator {
    public func showBigNotice(_ notice: HUDBigNotice) {
        shownBigNotices = Array((shownBigNotices + [notice]).suffix(5))
        callMovie { HUDMovieBridge.showBigNotice(notice, runtime: $0) }
    }

    /// A plain notice line with its sound.
    public func showNotification(_ text: String, sound: String) {
        showNotification(text)
        renderer?.swfSoundPlayer?(sound)
    }
}
