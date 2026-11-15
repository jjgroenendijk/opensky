// The Controls list rows that the control map adds beyond the keyboard: the mouse
// attack rows, Tween Menu, Favorites, Auto-Move, and Toggle Always Run.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyRendering
import Testing

struct InputBindingsMouseTests {
    private static let file = """
    // Main Gameplay
    Forward\t0x11\t0xff\t0xff\t1\t1\t0\t0x801
    Left Attack/Block\t0xff\t0x1\t0x0009\t1\t1\t1\t0x841
    Right Attack/Block\t0xff\t0x0\t0x000a\t1\t1\t1\t0x841
    Tween Menu\t0x0f\t0xff\t0x2000\t1\t1\t1\t0x908
    Quicksave\t0x3f\t0xff\t0xff\t1\t0\t0

    """

    @Test func theMouseColumnBindsAttackAndBlock() throws {
        let bindings = try InputBindings(controlMap: ControlMapFile(data: Data(Self.file.utf8)))
        #expect(bindings.scanCode(for: .attack) == InputCode.mouse(0))
        #expect(bindings.scanCode(for: .block) == InputCode.mouse(1))
        #expect(bindings.action(forMouseButton: 0) == .attack)
        #expect(bindings.action(forMouseButton: 1) == .block)
        #expect(bindings.scanCode(for: .tweenMenu) == 0x0F)
        #expect(bindings.action(forMacKey: 48, inMenu: false) == .tweenMenu, "Tab")
    }

    @Test func aMouseButtonBindsOnlyWhereTheFileAllowsIt() throws {
        var bindings = try InputBindings(controlMap: ControlMapFile(data: Data(Self.file.utf8)))
        #expect(bindings.rebind(.quicksave, to: InputCode.mouse(2)) == .notRemappable)
        #expect(bindings.rebind(.forward, to: InputCode.mouse(2)) == .bound)
        #expect(bindings.action(forMouseButton: 2) == .forward)
        #expect(bindings.rebind(.attack, to: InputCode.mouse(2)) == .swapped(with: .forward))
        #expect(bindings.scanCode(for: .forward) == InputCode.mouse(0))
        #expect(bindings.rebind(.forward, to: InputCode.mouse(40)) == .unknownKey)
    }

    @Test func savedMouseBindingsSurviveARestore() {
        var bindings = InputBindings()
        bindings.restore(["Main Gameplay|Jump": Int(InputCode.mouse(3)), "Main Gameplay|Run": 9999])
        #expect(bindings.scanCode(for: .jump) == InputCode.mouse(3))
        #expect(bindings.scanCode(for: .run) == 0x2A)
    }

    @Test func autoMoveIsUnboundOnAMac() {
        let bindings = InputBindings()
        #expect(bindings.scanCode(for: .autoMove) == nil, "C is Sneak")
        #expect(bindings.scanCode(for: .toggleAlwaysRun) == 0x3A)
        #expect(bindings.scanCode(for: .favorites) == 0x10)
        #expect(InputCode.mouseName(InputCode.mouse(0)) == "Mouse1")
        #expect(InputCode.mouseName(0x11) == nil)
    }

    @Test @MainActor
    func autoMoveWalksUntilForwardOrBack() {
        let state = CameraInputState()
        state.toggleAutoMove()
        #expect(state.makeInput(dt: 0.1).moveForward == 1)
        state.press(.back)
        state.release(.back)
        #expect(state.makeInput(dt: 0.1).moveForward == 0)
    }

    @Test @MainActor
    func theRunKeyFlipsAlwaysRun() {
        let state = CameraInputState()
        #expect(state.makeInput(dt: 0.1).isRunning, "always run is on by default")
        state.setBoost(true)
        #expect(!state.makeInput(dt: 0.1).isRunning)
        state.toggleAlwaysRun()
        #expect(state.makeInput(dt: 0.1).isRunning)
    }
}
