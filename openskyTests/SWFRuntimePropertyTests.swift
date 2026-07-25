// The display-property surface and the runtime text path (milestone 8.3.2
// phase 2).
//
// The twips-versus-pixels conversion is the thing worth pinning: ActionScript
// property units are pixels and degrees, the display list is twips and matrix
// terms, and a wrong factor of 20 misplaces every menu without erroring. Each
// conversion below asserts both directions.

import Foundation
@testable import opensky
import Testing

struct SWFRuntimePropertyTests {
    private func startedPanel() throws -> (SWFMovieRuntime, SWFDisplayObject) {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        let panel = try #require(runtime.root.child(named: "panel"))
        return (runtime, panel)
    }

    // MARK: - Position

    @Test func positionReadsAndWritesInPixelsOverTwips() throws {
        let (runtime, panel) = try startedPanel()
        // The fixture places the panel at 400/300 twips = 20/15 pixels.
        #expect(runtime.displayProperty(.positionX, of: panel) == .number(20))
        #expect(runtime.displayProperty(.positionY, of: panel) == .number(15))
        #expect(runtime.setDisplayProperty(.positionX, of: panel, to: .number(12.5)))
        #expect(panel.matrix.translateX == 250)
        #expect(runtime.displayProperty(.positionX, of: panel) == .number(12.5))
        #expect(runtime.setDisplayProperty(.positionY, of: panel, to: .string("-3")))
        #expect(panel.matrix.translateY == -60)
    }

    @Test func aNonFinitePositionClampsInsteadOfTrapping() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.setDisplayProperty(.positionX, of: panel, to: .number(.nan)))
        #expect(panel.matrix.translateX == 0)
        #expect(runtime.setDisplayProperty(.positionX, of: panel, to: .number(1e30)))
        #expect(panel.matrix.translateX == Int32.max)
    }

    // MARK: - Scale, size, rotation, alpha

    @Test func scaleIsAPercentageOfTheBasisVectors() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.displayProperty(.scaleX, of: panel) == .number(100))
        #expect(runtime.setDisplayProperty(.scaleX, of: panel, to: .number(50)))
        #expect(panel.matrix.scaleX == 0.5)
        #expect(runtime.setDisplayProperty(.scaleY, of: panel, to: .number(200)))
        #expect(panel.matrix.scaleY == 2)
        #expect(runtime.displayProperty(.scaleY, of: panel) == .number(200))
    }

    @Test func widthAndHeightReportTheTransformedBoundingBoxInPixels() throws {
        let (runtime, panel) = try startedPanel()
        // The rectangle inside the sprite is 2000 x 1200 twips = 100 x 60 px.
        #expect(runtime.displayProperty(.width, of: panel) == .number(100))
        #expect(runtime.displayProperty(.height, of: panel) == .number(60))
        #expect(runtime.setDisplayProperty(.width, of: panel, to: .number(50)))
        #expect(panel.matrix.scaleX == 0.5)
        #expect(runtime.displayProperty(.width, of: panel) == .number(50))
    }

    @Test func rotationIsDegreesAndPreservesScale() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.displayProperty(.rotation, of: panel) == .number(0))
        #expect(runtime.setDisplayProperty(.rotation, of: panel, to: .number(90)))
        let rotation = runtime.displayProperty(.rotation, of: panel)
        #expect(abs(AS2Fixture.number(rotation) - 90) < 0.001)
        let scale = runtime.displayProperty(.scaleX, of: panel)
        #expect(abs(AS2Fixture.number(scale) - 100) < 0.001)
        // A 2000 x 1200 twip box turns into 1200 x 2000 twips = 60 x 100 px.
        let width = runtime.displayProperty(.width, of: panel)
        #expect(abs(AS2Fixture.number(width) - 60) < 0.001)
    }

    @Test func alphaIsAPercentageOfTheColorTransformMultiplier() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.displayProperty(.alpha, of: panel) == .number(100))
        #expect(runtime.setDisplayProperty(.alpha, of: panel, to: .number(40)))
        #expect(abs(panel.colorTransform.multiply.w - 0.4) < 0.0001)
        #expect(runtime.displayProperty(.visible, of: panel) == .boolean(true))
        #expect(runtime.setDisplayProperty(.visible, of: panel, to: .number(0)))
        #expect(panel.isVisible == false)
    }

    // MARK: - Identity and timeline properties

    @Test func identityAndTimelinePropertiesReportTheNode() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.displayProperty(.name, of: panel) == .string("panel"))
        #expect(runtime.displayProperty(.target, of: panel) == .string("/panel"))
        #expect(runtime.displayProperty(.currentFrame, of: panel) == .number(1))
        #expect(runtime.displayProperty(.totalFrames, of: panel) == .number(1))
        #expect(runtime.setDisplayProperty(.name, of: panel, to: .string("renamed")))
        #expect(panel.name == "renamed")
    }

    /// Read-only members are answered rather than declined, so they do not
    /// crowd the missing-API tally with things that will never be implemented.
    @Test func readOnlyPropertiesAnswerAndRefuseWrites() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.displayProperty(.quality, of: panel) == .string("HIGH"))
        #expect(runtime.displayProperty(.mouseX, of: panel) == .number(0))
        #expect(runtime.setDisplayProperty(.currentFrame, of: panel, to: .number(3)) == false)
        #expect(runtime.setDisplayProperty(.target, of: panel, to: .string("/x")) == false)
    }

    // MARK: - Through the host seam

    @Test func propertiesReachTheNodeThroughMemberNames() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.member("_x", of: panel) == .number(20))
        #expect(runtime.setMember("_x", of: panel, to: .number(4)))
        #expect(panel.matrix.translateX == 80)
    }

    /// CLIK stores `__width` / `__height` as ordinary properties. Declining
    /// them here is what lets the interpreter fall back to the property table.
    @Test func doubleUnderscoreSizeNamesAreNotDisplayProperties() throws {
        let (runtime, panel) = try startedPanel()
        #expect(AS2DisplayProperty.named("__width") == nil)
        #expect(runtime.setMember("__width", of: panel, to: .number(7)) == false)
        panel.object.assign(.number(7), for: "__width")
        #expect(panel.object.lookup("__width")?.property.value == .number(7))
    }

    // MARK: - Text

    private static func textMovie(variableName: String = "") -> [SWFFixture.Tag] {
        var builder = SWFEditTextBodyBuilder()
        builder.characterId = 3
        builder.bounds = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 800)
        builder.flags.hasText = true
        builder.initialText = "AB"
        builder.variableName = variableName
        return [
            SWFFixture.Tag(code: 37, body: builder.build()),
            SWFRuntimeFixture.place(3, depth: 1, name: "field"),
            SWFDisplayFixture.showFrameTag
        ]
    }

    @Test func assignedTextOverridesTheAuthoredContentAndReachesTheScene() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.textMovie())
        let field = try #require(runtime.root.child(named: "field"))
        #expect(runtime.text(of: field) == "AB")
        #expect(SWFRuntimeFixture.drawItems(runtime.makeScene()).first?.textOverride == "AB")
        #expect(runtime.setMember("text", of: field, to: .string("CD")))
        #expect(runtime.member("text", of: field) == .string("CD"))
        let item = try #require(SWFRuntimeFixture.drawItems(runtime.makeScene()).first)
        #expect(item.content == .editText(3))
        #expect(item.textOverride == "CD")
    }

    @Test func aVariableBoundFieldReadsAndWritesThatVariable() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.textMovie(variableName: "message"))
        let field = try #require(runtime.root.child(named: "field"))
        // Nothing assigned yet, so the authored InitialText still shows.
        #expect(runtime.text(of: field) == "AB")
        runtime.root.object.assign(.string("bound"), for: "message")
        #expect(runtime.text(of: field) == "bound")
        // Writing the field writes the variable back.
        runtime.setText("typed", of: field)
        #expect(runtime.root.object.lookup("message")?.property.value == .string("typed"))
    }

    @Test func textMembersAreOnlyForEditTextNodes() throws {
        let (runtime, panel) = try startedPanel()
        #expect(runtime.member("text", of: panel) == nil)
        #expect(runtime.setMember("text", of: panel, to: .string("x")) == false)
    }
}
