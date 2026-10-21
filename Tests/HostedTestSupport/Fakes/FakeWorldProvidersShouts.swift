// The shout seam for the fake world: no load order, so nothing can be taught or shouted.

@testable import OpenSky
import OpenSkyFormatsESM
import OpenSkyMagic

extension FakeWorldProviders {
    var shoutSnapshot: ShoutControlSnapshot {
        .unavailable
    }

    func learnShout(_: ReferenceKey) -> ShoutOutcome {
        .unavailable
    }

    func equipShout(_: ReferenceKey) -> ShoutOutcome {
        .unavailable
    }

    func unlockNextWord(of _: ReferenceKey) -> ShoutOutcome {
        .unavailable
    }

    func addDragonSoul() {}

    func shout(words _: Int) -> ShoutOutcome {
        .unavailable
    }
}
