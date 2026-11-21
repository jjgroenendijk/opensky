// The HTML of a text field taken apart: font spans, paragraph alignment, line breaks, and
// character entities. Strings are built in code.

@testable import OpenSkyFormatsSWF
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFHTMLStylesTests {
    @Test func aFontTagStartsASpanAndItsCloseReturnsToTheOuterOne() {
        let content = SWFHTMLText.parseStyled(
            "<font face='$EverywhereFont' size='20' color='#102030'>A"
                + "<font color='#FFFFFF'>B</font>C</font>D"
        )
        #expect(content.text == "ABCD")
        let spans = content.styles.spans
        #expect(spans.map(\.start) == [0, 1, 2, 3])
        #expect(spans[0].color == SWFColor(red: 0x10, green: 0x20, blue: 0x30, alpha: 255))
        #expect(spans[0].sizeTwips == 400)
        #expect(spans[1].face == "$EverywhereFont", "an inner tag keeps the outer face")
        #expect(spans[2] == spans[0].restarted(at: 2))
        #expect(spans[3] == SWFTextStyleSpan(start: 3))
    }

    @Test func paragraphsAndBreaksEndLinesButNotTheText() {
        let content = SWFHTMLText
            .parseStyled("<p align='center'>A<br>B</p><P ALIGN=\"right\">C</P>")
        #expect(content.text == "A\rB\rC")
        #expect(content.styles.alignments == [0: 2, 2: 1])
        #expect(SWFHTMLText.parseStyled("<p>A</p><br>").text == "A\r\r")
    }

    @Test func entitiesDecodeAndAnUnknownOneStays() {
        #expect(SWFHTMLText.parseStyled("a &amp; b &lt;c&gt; &quot;&apos;&#65;&#x42;")
            .text == "a & b <c> \"'AB")
        #expect(SWFHTMLText.parseStyled("&nope; &").text == "&nope; &")
        #expect(SWFHTMLText.parseStyled("&toolongname x").text == "&toolongname x")
    }

    @Test func anImageStaysAMarkerAndABadColourIsIgnored() {
        let content = SWFHTMLText
            .parseStyled("<font color='red'>x<img src='E.png' width='8'></font>")
        #expect(content.text == "x\u{FFFC}")
        #expect(content.images.first?.source == "E.png")
        #expect(content.styles.spans.isEmpty, "a tag that changes nothing adds no span")
        #expect(SWFHTMLText.color("#ABCDEF") == SWFColor(
            red: 0xAB,
            green: 0xCD,
            blue: 0xEF,
            alpha: 255
        ))
        #expect(SWFHTMLText.color("#ABC") == nil)
    }
}
