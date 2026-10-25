// The batch file that puts the reference game at OpenSky's view.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferenceConsoleBatchTests {
    private func view(place: ReferencePlace, yaw: Float = 0, pitch: Float = 0) -> ReferenceView {
        ReferenceView(
            feet: SIMD3(1000.5, -2000.25, 300), yawDegrees: yaw, pitchDegrees: pitch,
            fovYDegrees: 65, gameHour: 13.5, place: place, weatherFormID: 0x0010_E1EC,
            firstPerson: true
        )
    }

    private let noToggles = ReferenceBatchToggles(hideMenus: false, freezeWorld: false)

    @Test func exteriorGoesToTheWorldspaceCellThenThePosition() throws {
        let place = ReferencePlace.exterior(worldspace: "Tamriel", grid: SIMD2(4, -8))
        let lines = try ReferenceConsoleBatch.lines(for: view(place: place), toggles: noToggles)
        #expect(lines == [
            "cow Tamriel 4 -8",
            "player.setpos x 1000.50", "player.setpos y -2000.25", "player.setpos z 300.00",
            "player.setangle x 0.00", "player.setangle z 90.00",
            "set gamehour to 13.50", "fw 0010E1EC", "fov 80.69"
        ])
    }

    @Test func interiorCentersOnTheCellByEditorID() throws {
        let lines = try ReferenceConsoleBatch.lines(
            for: view(place: .interior(editorID: "WhiterunBanneredMare")), toggles: noToggles
        )
        #expect(lines.first == "coc WhiterunBanneredMare")
    }

    @Test func togglesComeLastInOrder() throws {
        let toggles = ReferenceBatchToggles(hideMenus: true, freezeWorld: true)
        let lines = try ReferenceConsoleBatch.lines(
            for: view(place: .interior(editorID: "A")), toggles: toggles
        )
        #expect(lines.suffix(2) == ["tm", "tfc 1"])
    }

    @Test func textUsesWindowsLineEnds() throws {
        let text = try ReferenceConsoleBatch.text(
            for: view(place: .interior(editorID: "A")), toggles: noToggles
        )
        #expect(text.hasPrefix("coc A\r\nplayer.setpos x"))
        #expect(text.hasSuffix("\r\n"))
    }

    @Test func aViewWithoutAPlaceThrows() {
        var bare = view(place: .interior(editorID: "A"))
        bare.interiorEditorID = nil
        #expect(throws: ReferenceConsoleBatchError.noPlace) {
            try ReferenceConsoleBatch.lines(for: bare, toggles: noToggles)
        }
    }

    @Test func headingTurnsClockwiseFromNorth() {
        let place = ReferencePlace.interior(editorID: "A")
        #expect(view(place: place, yaw: 90).skyrimHeadingDegrees == 0)
        #expect(view(place: place, yaw: 0).skyrimHeadingDegrees == 90)
        #expect(view(place: place, yaw: -90).skyrimHeadingDegrees == 180)
        #expect(view(place: place, yaw: 180).skyrimHeadingDegrees == 270)
    }

    @Test func lookingUpIsANegativeConsolePitch() {
        #expect(view(place: .interior(editorID: "A"), pitch: 20).skyrimPitchDegrees == -20)
    }

    @Test func viewRoundTripsThroughJSON() throws {
        let original = view(place: .exterior(worldspace: "Tamriel", grid: SIMD2(1, 2)))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ReferenceView.self, from: data) == original)
    }
}
