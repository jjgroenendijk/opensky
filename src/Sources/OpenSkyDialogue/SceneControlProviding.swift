// The Scenes section's seam: the catalog search, start and stop, the playing
// scenes, and the last steps and lines. The text lives in `SceneCore`, so it is
// testable without a window. See docs/engine/scenes.md.

import Foundation
public import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyWorldState

extension SceneCoordinator {
    public var sceneSnapshot: SceneControlSnapshot {
        let limit = SceneControlSnapshot.rowLimit
        let playingRows = catalog.all.compactMap { entry -> ScenePlayingRow? in
            guard let state = dialogue.store.component(SceneRuntimeState.self, for: entry.key)
            else { return nil }
            return SceneCore.playingRow(entry, state: state)
        }
        return SceneControlSnapshot(
            playing: Array(playingRows.prefix(limit)),
            trace: trace.suffix(limit).map { SceneCore.text($0, catalog: catalog) },
            lines: lines.suffix(limit).map(SceneCore.text(line:))
        )
    }
}
