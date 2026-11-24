// The two PKDT flags that make an owner unlock its doors: one at the package's start, one
// when the package changes. See docs/engine/crime.md#opened-by-the-owner.

import Foundation
@testable import OpenSkyAIPackages
@testable import OpenSkyFormatsESM
import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

struct PackageDoorFlagTests {
    private static func event(
        _ kind: PackageScriptEvent.Kind, flags: Package.GeneralFlags
    ) throws -> PackageScriptEvent {
        try PackageScriptEvent(
            kind: kind, actor: .generated(1),
            package: PackageRuntimeFixture.package(id: 0x800, flags: flags)
        )
    }

    @Test func eachFlagUnlocksOnlyAtItsOwnMoment() throws {
        #expect(try Self.event(.begin, flags: .unlockDoorsAtStart).unlocksDoors)
        #expect(try !Self.event(.change, flags: .unlockDoorsAtStart).unlocksDoors)
        #expect(try Self.event(.change, flags: .unlockDoorsOnChange).unlocksDoors)
        #expect(try !Self.event(.begin, flags: .unlockDoorsOnChange).unlocksDoors)
        #expect(try !Self.event(.end, flags: [.unlockDoorsAtStart, .unlockDoorsOnChange])
            .unlocksDoors)
    }
}
