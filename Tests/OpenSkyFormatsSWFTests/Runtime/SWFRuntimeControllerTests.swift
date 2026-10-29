// GFx controllers, the `SetPlatform` platform, and CLIK's optional `focusIndicator`.
// Synthetic fixtures only.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeControllerTests {
    typealias Action = AS2Fixture.Action

    private func started(_ actions: [Action] = []) throws -> SWFMovieRuntime {
        var tags = SWFRuntimeFixture.classMovieTags()
        tags.insert(SWFActionFixture.doActionTag(actions), at: tags.count - 1)
        return try SWFRuntimeFixture.started(tags: tags)
    }

    /// `result = panel.<name>`, read through the interpreter's member path.
    private func readMember(_ name: String) -> [Action] {
        [AS2Fixture.push([.string("result")])] + AS2Fixture.getVariable("panel")
            + [AS2Fixture.push([.string(name)]), AS2Fixture.opcode(0x4E), AS2Fixture.opcode(0x1D)]
    }

    private func numControllers(_ runtime: SWFMovieRuntime) throws -> AS2Value? {
        let system = try #require(runtime.runtime.globalValue("System").objectValue)
        let capabilities = system.lookup("capabilities")?.property.value.objectValue
        return capabilities?.lookup("numControllers")?.property.value
    }

    @Test func keyboardAndMouseAreOneController() throws {
        let runtime = try started()
        #expect(try numControllers(runtime) == .integer(1))
        #expect(runtime.focusGroupControllerMask == 1)
        #expect(runtime.inputPlatform == SWFMovieRuntime.keyboardPlatform)
    }

    @Test func aGamepadAddsAControllerToFocusGroupZero() throws {
        let runtime = try started()
        runtime.setGamepadCount(1)
        #expect(try numControllers(runtime) == .integer(2))
        #expect(runtime.focusGroupControllerMask == 0b11)
        #expect(runtime.inputPlatform == SWFMovieRuntime.gamepadPlatform)
        runtime.setGamepadCount(9)
        #expect(runtime.controllerCount == 1 + SWFMovieRuntime.maximumGamepads)
    }

    @Test func setPlatformCarriesTheRuntimePlatformAndIsSentAgain() throws {
        let runtime = try started()
        let log = SWFGameDelegateTests.CallLog()
        AS2Natives.method(runtime.runtime, on: runtime.root.object, name: "SetPlatform") {
            log.append($0.arguments)
            return .undefined
        }
        runtime.callMovie("SetPlatform", arguments: [.number(0), .boolean(false)])
        runtime.setGamepadCount(1)
        runtime.setGamepadCount(1)
        runtime.setGamepadCount(0)
        #expect(log.calls.map(\.first) == [.number(0), .number(1), .number(0)])
        #expect(log.calls.allSatisfy { $0.last == .boolean(false) })
    }

    @Test func unsetComponentMembersAreUndefinedWithoutATally() throws {
        let names = SWFMovieRuntime.unsetComponentMembers.sorted()
        let runtime = try started(names.flatMap(readMember) + readMember("unknownChild"))
        #expect(runtime.root.object.lookup("result")?.property.value == .undefined)
        for name in names {
            #expect(runtime.tally.missingNames[name] == nil, "\(name)")
        }
        #expect(runtime.tally.missingNames["unknownChild"] == 1)
    }

    @Test func currentFrameLabelIsTheLastLabelAtOrBeforeThePlayhead() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 3, tags: [
                SWFDisplayFixture.frameLabelTag("up"), SWFDisplayFixture.showFrameTag,
                SWFDisplayFixture.showFrameTag,
                SWFDisplayFixture.frameLabelTag("over"), SWFDisplayFixture.showFrameTag
            ]),
            SWFRuntimeFixture.place(2, depth: 1, name: "button"),
            SWFDisplayFixture.showFrameTag
        ])
        let button = try #require(runtime.root.child(named: "button"))
        runtime.gotoFrame(1, of: button, play: false)
        #expect(runtime.currentFrameLabel(of: button) == "up")
        runtime.gotoLabel("over", of: button, play: false)
        #expect(runtime.currentFrameLabel(of: button) == "over")
    }
}
