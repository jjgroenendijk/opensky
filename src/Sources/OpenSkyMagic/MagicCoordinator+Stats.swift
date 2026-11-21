// The magic stats on the journal's Stats page. See docs/engine/statistics.md.

import OpenSkyQuestsInterface

extension MagicCoordinator {
    /// Raises a journal stat in the session's store. A session without one counts nothing.
    func incrementStat(_ name: String) {
        (effects?.store ?? caster?.spellbook.store)?.incrementMiscStat(name)
    }
}
