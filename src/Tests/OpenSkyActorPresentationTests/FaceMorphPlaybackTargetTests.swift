// Face playback sends its weights to every bound morph target and refuses unknown ones.

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import Testing

struct FaceMorphPlaybackTargetTests {
    @Test func aWeightReachesTheBoundTarget() {
        let target = FakeFaceMorphTarget(targetNames: ["Blink"])
        let playback = FaceMorphPlayback(
            actor: FormID(0x7), bindings: [ObjectIdentifier(target): target],
            pairedPaths: [], misses: []
        )
        #expect(playback.setWeight(0.5, for: "Blink"))
        #expect(!playback.setWeight(1, for: "Smile"))
        #expect(playback.unknownTargetCount == 1)
        #expect(target.uploads.last?["Blink"] == 0.5)
    }
}
