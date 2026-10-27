// Script sound instances: IDs, a stop or volume before the source starts, and the
// `PlayAndWait` answers.

@testable import OpenSkyWorld
import Testing

struct ScriptSoundInstancesTests {
    @Test func aStopBeforeTheSourceStartsRefusesIt() {
        var sounds = ScriptSoundInstances()
        let id = sounds.begin(waitToken: 9)
        #expect(id != 0)
        #expect(sounds.setVolume(id, 4) == nil)
        #expect(sounds.volume(of: id) == 1)
        #expect(sounds.stop(id) == nil)
        #expect(sounds.adopt(id, source: 3) == .init(keeps: false, volume: nil))
        #expect(sounds.retire(playing: [], failed: []) == [9: false])
        #expect(sounds.isEmpty)
    }

    @Test func aSoundThatEndsAnswersItsWait() {
        var sounds = ScriptSoundInstances()
        let played = sounds.begin(waitToken: 1)
        let broken = sounds.begin(waitToken: 2)
        #expect(sounds.setVolume(played, 0.5) == nil)
        #expect(sounds.adopt(played, source: 7) == .init(keeps: true, volume: 0.5))
        #expect(sounds.setVolume(played, -1) == 7)
        #expect(sounds.retire(playing: [7], failed: [broken]) == [2: false])
        #expect(sounds.retire(playing: [], failed: []) == [1: true])
        #expect(sounds.isEmpty)
    }
}
