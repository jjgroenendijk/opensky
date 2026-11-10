// `TextField` members CLIK and the vanilla menus use beyond text and scrolling:
// `createTextField`, `selectable`, and the text format calls.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFRuntimeTextFieldTests {
    private func call(
        _ runtime: SWFMovieRuntime,
        _ name: String,
        on node: SWFDisplayObject,
        _ arguments: [AS2Value] = []
    ) throws -> AS2Value {
        let member = node.object.lookup(name)?.property.value ?? runtime.member(name, of: node)
        let function = try #require(member?.functionValue)
        return AS2Interpreter.invoke(
            in: runtime.runtime,
            .object(function),
            thisValue: .object(node.object),
            arguments: arguments
        ).value
    }

    /// The quest journal makes its hidden `LevelText` field this way.
    private func createdField(_ runtime: SWFMovieRuntime) throws -> SWFDisplayObject {
        let created = try call(
            runtime, "createTextField", on: runtime.root,
            [.string("LevelText"), .number(3), .number(10), .number(5), .number(200), .number(30)]
        )
        return try #require(SWFDisplayObject.resolve(created.objectValue))
    }

    @Test func createTextFieldPlacesANamedFieldOfTheGivenSize() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let field = try createdField(runtime)
        #expect(runtime.root.child(named: "LevelText") === field)
        #expect(runtime.member("_x", of: field) == .number(10))
        #expect(runtime.member("_y", of: field) == .number(5))
        #expect(runtime.member("_width", of: field) == .number(200))
        #expect(runtime.member("_height", of: field) == .number(30))
        #expect(runtime.setMember("text", of: field, to: .string("$Level")))
        #expect(runtime.member("text", of: field) == .string("$Level"))
        #expect(runtime.tally.missingNames["createTextField"] == nil)
    }

    @Test func twoCreatedFieldsKeepTheirOwnDefinitions() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let first = try createdField(runtime)
        let second = try SWFDisplayObject.resolve(call(
            runtime, "createTextField", on: runtime.root,
            [.string("Other"), .number(4), .number(0), .number(0), .number(50), .number(20)]
        ).objectValue)
        #expect(first.characterId != second?.characterId)
        #expect(runtime.member("_width", of: first) == .number(200))
        #expect(try runtime.member("_width", of: #require(second)) == .number(50))
    }

    /// `_width` on a field sets its unscaled box; only `_xscale` scales it. CLIK's
    /// `Constraints` counts on this when it lays out a scaled button's label.
    @Test func settingTheWidthResizesTheUnscaledBox() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let field = try createdField(runtime)
        #expect(runtime.setMember("_xscale", of: field, to: .number(50)))
        #expect(runtime.member("_width", of: field) == .number(100))
        #expect(runtime.setMember("_width", of: field, to: .number(300)))
        #expect(runtime.setMember("_height", of: field, to: .number(60)))
        #expect(runtime.member("_xscale", of: field) == .number(50))
        #expect(runtime.member("_width", of: field) == .number(150))
        #expect(runtime.member("_height", of: field) == .number(60))
        #expect(runtime.textField(of: field)?.bounds.xMax == Int32(6000))
        #expect(runtime.hitTest(stageTwips: SIMD2(150 * 20, 50 * 20)).topmost === field)
        #expect(runtime.hitTest(stageTwips: SIMD2(170 * 20, 50 * 20)).topmost !== field)
    }

    /// DefineEditText `NoSelect` clear means selectable, as Flash reports it.
    @Test func aFieldIsSelectableUnlessItsCharacterSaysNot() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let field = try createdField(runtime)
        #expect(runtime.member("selectable", of: field) == .boolean(true))
        #expect(runtime.member("selectable", of: runtime.root) == nil)
    }

    @Test func theNewTextFormatCallsAnswer() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let field = try createdField(runtime)
        #expect(try call(runtime, "getNewTextFormat", on: field).objectValue != nil)
        #expect(try call(runtime, "setNewTextFormat", on: field, [.null]) == .undefined)
    }
}
