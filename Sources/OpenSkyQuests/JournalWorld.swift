// The world side of the journal: what `JournalCoordinator` reads from the
// running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyGameData

/// What `JournalCoordinator` reads from the running world.
@MainActor
public protocol JournalWorld: AnyObject {
    /// Nil without game data.
    var questRuntime: QuestRuntime? { get }
    /// Walks the VFS, so the coordinator calls it once.
    func loadStrings() -> LocalizedStrings?
}
