// Which clip annotations a graph of the clip's own project waits for. Paths follow
// the install's folder shapes; the event names are invented.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct HKXAnnotationHearingTests {
    @Test func projectIsTheFolderAboveAnimationsOrBehaviors() {
        #expect(HKXAnnotationHearing.project(of: "meshes\\actors\\canine\\animations\\run.hkx")
            == "meshes\\actors\\canine\\")
        #expect(HKXAnnotationHearing
            .project(of: "meshes\\actors\\canine\\behaviors wolf\\quadrupedbehavior.hkx")
            == "meshes\\actors\\canine\\")
        #expect(HKXAnnotationHearing
            .project(of: "Meshes\\Actors\\Character\\Animations\\DLC01\\Bolt.hkx")
            == "meshes\\actors\\character\\")
    }

    @Test func onlyTheClipsOwnProjectHearsIt() {
        var hearing = HKXAnnotationHearing()
        hearing.addAnnotation("TestWindowStart", clipPath: "meshes\\actors\\a\\animations\\x.hkx")
        hearing.addAnnotation("TestOpen", clipPath: "meshes\\actors\\a\\animations\\x.hkx")
        hearing.addListened(["testwindowstart"], graphPath: "meshes\\actors\\a\\behaviors\\b.hkx")
        hearing.addListened(["TestOpen"], graphPath: "meshes\\doors\\behaviors\\door.hkx")
        #expect(hearing.heardEvents() == ["testwindowstart"])
    }

    @Test func aHeardPayloadEventIsFolded() {
        var hearing = HKXAnnotationHearing()
        hearing.addAnnotation("TestCue.Loud", clipPath: "m\\animations\\x.hkx")
        hearing.addListened(["TestCue.Loud"], graphPath: "m\\behaviors\\b.hkx")
        #expect(hearing.heardEvents() == ["testcue.*"])
    }
}
