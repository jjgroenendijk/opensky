// A dependent animated object takes its owner's idle events, each actor once.

import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

@MainActor
struct IdleDependentsTests {
    private static func actor(_ id: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: id)
    }

    @Test func dependentsFollowTheirOwnerInOrderOnce() {
        let idles = IdleCoordinator()
        idles.addDependent(Self.actor(2), of: Self.actor(1))
        idles.addDependent(Self.actor(3), of: Self.actor(1))
        idles.addDependent(Self.actor(1), of: Self.actor(3))
        idles.addDependent(Self.actor(2), of: Self.actor(1))
        #expect(idles.withDependents(Self.actor(1)) == [1, 2, 3].map(Self.actor))
        idles.removeDependent(Self.actor(2), of: Self.actor(1))
        #expect(idles.withDependents(Self.actor(1)) == [1, 3].map(Self.actor))
    }
}
