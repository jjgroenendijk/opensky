// The discovery music a map marker type picks (docs/engine/music.md#discovery-music).

import OpenSkyAudio
import Testing

struct DiscoveryMusicTests {
    @Test func theMarkerTypeAloneNamesTheMusic() {
        #expect(DiscoveryMusic.editorID(markerType: 1) == "MUSDiscoveryCity")
        #expect(DiscoveryMusic.editorID(markerType: 2) == "MUSDiscoveryTown")
        for dungeon: UInt8 in [4, 7, 8, 12, 15] {
            #expect(DiscoveryMusic.editorID(markerType: dungeon) == "MUSDiscoveryDungeon")
        }
        // Camp, fort, and the capitals' own types, such as Whiterun's 40.
        for other: UInt8 in [0, 3, 5, 6, 40, 50] {
            #expect(DiscoveryMusic.editorID(markerType: other) == "MUSDiscoveryGeneric")
        }
    }
}
