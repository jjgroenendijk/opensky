// The music director's readout for `state music`.

import OpenSkyAudio
public import OpenSkyWorldInterface

extension WorldMusicDirector {
    public var readout: MusicReadout {
        var music = MusicReadout()
        music.musicType = desiredSelection.displayName
        music.musicTypeFormID = desiredSelection.musicType
        music.state = desiredSelection.state.displayName
        music.trackPath = currentTrackName
        music.trackIndex = trackIndex
        music.trackCount = desiredSelection.tracks.count
        music.elapsedSeconds = currentTrackElapsedSeconds
        music.paused = pauses > 0
        music.combat = preCombatSelection != nil
        music.interruptedBySpecial = preSpecialSelection?.displayName
        music.scriptedMusic = scriptedMusic
        music.enabled = musicEnabled
        music.refusal = lastMusicError
        return music
    }
}
