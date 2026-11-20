// The menu blur: the `IMID` default object's modifier runs once while a blurring menu is open.

import Foundation
@testable import OpenSkyEffects
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyRenderCore
import Testing

@MainActor
struct EffectsCoordinatorMenuBlurTests {
    private static func records(withModifier: Bool) throws -> EffectRecordStore {
        var entries = Data("GOLD".utf8)
        entries.appendUInt32(0x0F)
        if withModifier {
            entries.append(contentsOf: Data("IMID".utf8))
            entries.appendUInt32(0x40)
        }
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("DOBJ", formID: 0x31, data: ESMFixture.field("DNAM", entries)),
            ESMFixture.record("IMAD", formID: 0x40, data: ESMFixture.field(
                "EDID", Data("ISMTween\0".utf8)
            ))
        ])
        return EffectRecordStore(plugins: [("Skyrim.esm", file)])
    }

    @Test func theModifierRunsOnceWhileWantedAndStopsAfter() throws {
        let effects = try EffectsCoordinator(records: Self.records(withModifier: true))
        var imageSpace = ImageSpaceState()
        effects.setMenuBlur(true, on: &imageSpace)
        effects.setMenuBlur(true, on: &imageSpace)
        #expect(effects.holdsMenuBlur)
        #expect(imageSpace.modifiers.instances.count == 1)
        #expect(imageSpace.modifiers.instances.first?.looping == true)
        #expect(imageSpace.modifiers.instances.first?.strength == 1)
        effects.setMenuBlur(false, on: &imageSpace)
        imageSpace.modifiers.advance(0)
        #expect(!effects.holdsMenuBlur)
        #expect(imageSpace.modifiers.instances.isEmpty)
    }

    @Test func noDefaultObjectStartsNothing() throws {
        let effects = try EffectsCoordinator(records: Self.records(withModifier: false))
        var imageSpace = ImageSpaceState()
        effects.setMenuBlur(true, on: &imageSpace)
        #expect(!effects.holdsMenuBlur)
        #expect(imageSpace.modifiers.instances.isEmpty)
    }
}
