// The riding seam of the fake world.

@testable import OpenSky
import OpenSkyFormatsESM
import OpenSkyPlayer

struct FakeMountState {
    var snapshot = MountControlSnapshot(
        readout: MountReadout(
            phase: .none, mount: nil, kind: nil, speed: 0, isSprinting: false,
            lastMount: nil, lastRefusal: nil, nearest: nil
        ),
        names: [:]
    )
    var mountNearestCalls = 0
    var dismountCalls = 0
}

extension FakeWorldProviders {
    var mountSnapshot: MountControlSnapshot {
        mount.snapshot
    }

    func mountNearest() {
        mount.mountNearestCalls += 1
    }

    func dismountPlayer() {
        mount.dismountCalls += 1
    }
}
