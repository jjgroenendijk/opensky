// Key bindings over the controlmap, the Mac key table, rebinding, and autosaves.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct InputBindingsTests {
    @Test
    func builtInDefaultsUseVanillaKeysAndTheMacOverrides() {
        let bindings = InputBindings()
        #expect(bindings.scanCode(for: .forward) == 0x11)
        #expect(bindings.scanCode(for: .activate) == 0x12)
        #expect(bindings.scanCode(for: .sneak) == 0x2E, "C, because Control-click is a right click")
        #expect(bindings.action(forMacKey: 13, inMenu: false) == .forward, "W")
        #expect(bindings.action(forMacKey: 14, inMenu: false) == .activate, "E")
        #expect(bindings.action(forMacKey: 7, inMenu: false) == .up, "X flies up")
        #expect(bindings.action(forMacKey: 56, inMenu: false) == .run, "left Shift")
        #expect(bindings.action(forMacKey: 53, inMenu: false) == .pause, "Esc")
    }

    @Test
    func menuKeysSteerMenus() {
        let bindings = InputBindings()
        #expect(bindings.action(forMacKey: 36, inMenu: true) == .menuAccept)
        #expect(bindings.action(forMacKey: 53, inMenu: true) == .menuCancel)
        #expect(bindings.action(forMacKey: 126, inMenu: true) == .menuUp)
    }

    @Test
    func rebindSwapsInsideTheContextAndRestoreDropsUnknownKeys() {
        var bindings = InputBindings()
        #expect(bindings.rebind(.forward, to: 0x1F) == .swapped(with: .back))
        #expect(bindings.scanCode(for: .forward) == 0x1F)
        #expect(bindings.scanCode(for: .back) == 0x11)
        #expect(bindings.isRemapped(.forward))
        #expect(bindings.rebind(.forward, to: 0xFE) == .unknownKey)
        let saved = bindings.overrides.mapValues(Int.init)
        var restored = InputBindings()
        restored.restore(saved.merging(["Nope|Event": 0x11, "Main Gameplay|Jump": -1]) { $1 })
        #expect(restored == bindings)
        restored.reset()
        #expect(restored == InputBindings())
    }

    @Test
    func everyScanCodeRoundTripsThroughTheMacTable() {
        for (scan, mac) in DirectInputKeyCodes.macKeyCodes {
            #expect(DirectInputKeyCodes.scanCode(mac) == scan)
        }
    }

    @Test @MainActor
    func autosaveFollowsTheSettingsAndRotatesSlots() {
        let store = PlayerSettingsStore(persistence: nil)
        let policy = AutosavePolicy()
        store.set(.saveOnRest, to: 1)
        store.set(.saveOnWait, to: 0)
        #expect(policy.isEnabled(.rest, settings: store))
        #expect(!policy.isEnabled(.wait, settings: store))
        let old = Date(timeIntervalSince1970: 1)
        let new = Date(timeIntervalSince1970: 2)
        let next = policy.nextSlot(saved: [
            AutosavePolicy.slot(1): new,
            AutosavePolicy.slot(2): old
        ])
        #expect(next == AutosavePolicy.slot(3), "an empty slot comes first")
        let full = policy.nextSlot(saved: [
            AutosavePolicy.slot(1): new, AutosavePolicy.slot(2): old, AutosavePolicy.slot(3): new
        ])
        #expect(full == AutosavePolicy.slot(2), "then the oldest")
    }

    @Test
    func aKeyTheFileMarksFixedCannotBeRebound() throws {
        let text = "// Main Gameplay\nForward\t0x11\t0xff\t0xff\t0\t0\t0\n"
        var bindings = try InputBindings(controlMap: ControlMapFile(data: Data(text.utf8)))
        #expect(bindings.rebind(.forward, to: 0x48) == .notRemappable)
        #expect(bindings.scanCode(for: .forward) == 0x11)
        #expect(bindings.rebind(.back, to: 0x48) == .bound)
    }
}
