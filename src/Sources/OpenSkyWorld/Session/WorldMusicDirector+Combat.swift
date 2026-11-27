// Combat music: entering combat swaps in the combat playlist, and leaving restores
// what it interrupted. See docs/engine/music.md.

import OpenSkyAudio
public import OpenSkyWorldInterface

extension WorldMusicDirector {
    /// Switches the combat playlist on and off. Entering selects a `MUSCombat...`
    /// record directly and remembers the interrupted selection; leaving restores it.
    /// With no combat playlist the music stays. See docs/engine/music.md.
    /// - Returns: nil on success, or a short reason the selection did not change.
    @discardableResult
    public func setCombatActive(_ active: Bool) -> MusicRefusal? {
        guard active else { return leaveCombat() }
        guard preCombatSelection == nil else { return nil }
        guard let musicStore else {
            lastMusicRefusal = .noMusicData
            return lastMusicRefusal
        }
        guard let combat = Self.combatMusicType(in: musicStore) else {
            lastMusicRefusal = .noCombatMusicType
            return lastMusicRefusal
        }
        let selection = MusicSelection
            .resolve(musicType: combat, musicStore: musicStore)
            .labelled(.combat)
        guard !selection.isSilent else {
            lastMusicRefusal = .noPlayableCombatTrack
            return lastMusicRefusal
        }
        // Combat cuts a special moment short and returns to what that interrupted.
        preCombatSelection = preSpecialSelection ?? desiredSelection
        preSpecialSelection = nil
        adopt(selection, force: true)
        lastMusicRefusal = nil
        return nil
    }

    /// Whether the combat playlist is the current selection.
    public var isCombatMusicActive: Bool {
        preCombatSelection != nil
    }

    /// Restores the selection combat interrupted.
    private func leaveCombat() -> MusicRefusal? {
        guard let previous = preCombatSelection else { return nil }
        preCombatSelection = nil
        adopt(previous, force: true)
        return nil
    }
}
