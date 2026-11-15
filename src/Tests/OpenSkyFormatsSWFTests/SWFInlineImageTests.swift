// Key art in help text: `<img>` tags in `htmlText`, their place in a line, and the
// `BitmapData.loadBitmap` native that reads an exported bitmap's size.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFInlineImageTests {
    @Test func anImageTagBecomesOneMarkerWithItsAttributes() {
        let parsed = SWFHTMLText.parse(
            "Hold <IMG SRC=\"L-Shift.png\" vspace='-5' height='26' width='30'> to <b>run</b>"
        )
        #expect(parsed.text == "Hold \u{FFFC} to run")
        #expect(parsed.images == [SWFInlineImage(
            source: "L-Shift.png", width: 30, height: 26, verticalSpace: -5
        )])
        #expect(SWFHTMLText.parse("<img width='3'>x").text == "x", "no src is no image")
        let restored = SWFHTMLText.restoringImages(in: parsed.text, images: parsed.images)
        #expect(SWFHTMLText.parse(restored).images == parsed.images)
    }

    @Test func loadBitmapAnswersAnExportedBitmapsSize() throws {
        var body = Data()
        body.appendUInt16(5)
        body.append(5)
        body.appendUInt16(3)
        body.appendUInt16(2)
        body.append(ZlibFixture.stream(Data(repeating: 0xFF, count: 3 * 2 * 4)))
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFFixture.Tag(code: 36, body: body),
            SWFDisplayFixture.exportAssetsTag([(5, "E.png")]),
            SWFDisplayFixture.showFrameTag
        ])
        let runtime = SWFMovieRuntime(movieScene: SWFMovieScene(movie: movie))
        runtime.start()
        let flash = try #require(runtime.runtime.globalValue("flash").objectValue)
        let display = try #require(flash.lookup("display")?.property.value.objectValue)
        let bitmapData = try #require(display.lookup("BitmapData")?.property.value.objectValue)
        let load = bitmapData.lookup("loadBitmap")?.property.value ?? .undefined
        let found = AS2Interpreter.invoke(
            in: runtime.runtime, load, thisValue: .object(bitmapData), arguments: [.string("E.png")]
        ).value
        let bitmap = try #require(found.objectValue)
        #expect(bitmap.lookup("width")?.property.value == .integer(3))
        #expect(bitmap.lookup("height")?.property.value == .integer(2))
        let missing = AS2Interpreter.invoke(
            in: runtime.runtime, load, thisValue: .object(bitmapData), arguments: [.string("Q.png")]
        ).value
        #expect(missing == .undefined)
    }
}
