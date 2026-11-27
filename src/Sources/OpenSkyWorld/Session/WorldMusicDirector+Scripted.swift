// Scripts' music: `MusicType.Add` and `Remove` stack music types over the cell's music.
// See docs/engine/music.md.

import OpenSkyAudio
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

extension WorldMusicDirector {
    /// `MusicType.Add`: the type joins the stack, and the stack's top plays over the
    /// cell's music. Adding it again makes it the newest. Returns nil on success or a
    /// short failure reason.
    @discardableResult
    public func addScriptedMusic(_ id: FormID) -> MusicRefusal? {
        guard let musicStore else {
            lastMusicRefusal = .noMusicData
            return lastMusicRefusal
        }
        let selection = MusicSelection.resolve(musicType: id, musicStore: musicStore)
        guard !selection.isSilent else {
            lastMusicRefusal = .noPlayableTrack(id)
            return lastMusicRefusal
        }
        let before = playingScriptedMusic
        scriptedMusic.removeAll { $0 == id }
        scriptedMusic.append(id)
        if playingScriptedMusic != before {
            playScriptedTop()
        }
        return nil
    }

    /// `MusicType.Remove`: the stack's next top plays, or the cell's music when none is left.
    public func removeScriptedMusic(_ id: FormID) {
        guard let index = scriptedMusic.lastIndex(of: id) else { return }
        let before = playingScriptedMusic
        scriptedMusic.remove(at: index)
        guard playingScriptedMusic != before else { return }
        playScriptedTop()
    }

    /// The scripted type that sounds: the highest `MUSC` priority, the newest on a tie.
    public var playingScriptedMusic: FormID? {
        ScriptedMusicStack.top(scriptedMusic) { musicStore?.musicType($0)?.priority }
    }

    private func playScriptedTop() {
        if let top = playingScriptedMusic, let musicStore {
            play(MusicSelection.resolve(musicType: top, musicStore: musicStore))
        } else {
            play(contextSelection)
        }
    }

    /// Combat keeps its own music; the selection waits for the fight to end.
    private func play(_ selection: MusicSelection) {
        if preCombatSelection != nil {
            preCombatSelection = selection
        } else if preSpecialSelection != nil {
            preSpecialSelection = selection
        } else {
            adopt(selection, force: true)
        }
    }
}
