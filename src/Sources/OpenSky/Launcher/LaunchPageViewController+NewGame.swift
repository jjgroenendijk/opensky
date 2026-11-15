// The Launch page's New game group: where a new game starts, and at a place, the story
// and the starting items.

import AppKit
import OpenSkyLaunch

extension LaunchPageViewController {
    func makeNewGameGroup() -> NSView {
        layout.group(
            "New game",
            [layout.row("Starts at", startPopUp)] + startOptions.rows + [startReasonLabel]
        )
    }

    /// Shows why Play is off for a new game, if it is.
    func refreshStart() {
        for row in startOptions.rows {
            row.isHidden = start == .normal
        }
        let reason = validStart == nil && context.isLoadingStartPlaces ? Self.readingTitle : nil
        startReasonLabel.stringValue = reason.map { "Play is off: \($0)" } ?? ""
        startReasonLabel.toolTip = startReasonLabel.stringValue
        startReasonLabel.isHidden = reason == nil
        refreshPlay()
    }
}
