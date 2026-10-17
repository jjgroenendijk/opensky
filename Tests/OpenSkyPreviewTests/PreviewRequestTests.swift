// Preview options, views, and request rules: which target and stage a set of options
// names, and which ones are refused.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyPreview
import simd
import Testing

struct PreviewRequestTests {
    @Test func allAnglesGiveFiveNamedViews() throws {
        let views = try PreviewAngle.views(named: "all")
        #expect(views.map(\.name) == ["front", "side", "back", "top", "three-quarter"])
    }

    @Test func anUnknownAngleIsRefused() {
        #expect(throws: PreviewError.unknownAngle("left")) {
            try PreviewAngle.views(named: "front,left")
        }
    }

    @Test func theFrontViewLooksFromPlusY() {
        let direction = PreviewView(name: "front", yaw: 0, pitch: 0).eyeDirection
        #expect(simd_distance(direction, SIMD3(0, 1, 0)) < 1e-5)
        let side = PreviewView(name: "side", yaw: 90, pitch: 0).eyeDirection
        #expect(simd_distance(side, SIMD3(1, 0, 0)) < 1e-5)
    }

    @Test func aRecordAloneRendersInTheStudio() throws {
        var options = PreviewOptions()
        options.record = "Bucket01"
        let request = try options.request()
        #expect(request.target == .record("Bucket01"))
        #expect(request.resolvedStage == .studio)
        #expect(request.views.map(\.name) == ["three-quarter"])
    }

    @Test func aRecordWithACellStandsInThatCell() throws {
        var options = PreviewOptions()
        options.record = "Bucket01"
        options.cell = "WhiterunBanneredMare"
        let request = try options.request()
        #expect(request.hostCell == .interiorCell("WhiterunBanneredMare"))
        #expect(request.resolvedStage == .cell)
    }

    @Test func aGridAloneIsAnExteriorCellTarget() throws {
        var options = PreviewOptions()
        options.worldspace = "DLC2SolstheimWorld"
        (options.x, options.y) = (7, 8)
        let request = try options.request()
        #expect(request.target == .exteriorCell(
            worldspace: "DLC2SolstheimWorld", grid: CellCoordinate(x: 7, y: 8)
        ))
        #expect(request.resolvedStage == .cell)
    }

    @Test func twoTargetsOrNoneAreRefused() {
        var options = PreviewOptions()
        #expect(throws: PreviewError.oneTarget) { try options.request() }
        options.record = "A"
        options.mesh = "b.nif"
        #expect(throws: PreviewError.oneTarget) { try options.request() }
    }

    @Test func halfAGridIsRefused() {
        var options = PreviewOptions()
        options.x = 3
        #expect(throws: PreviewError.badGrid) { try options.request() }
    }

    @Test func theCellStageNeedsACellForARecord() {
        var options = PreviewOptions()
        options.record = "A"
        options.stage = "cell"
        #expect(throws: PreviewError.cellStageNeedsCell) { try options.request() }
    }

    @Test func aCellCannotUseTheStudio() {
        var options = PreviewOptions()
        options.cell = "A"
        options.stage = "studio"
        #expect(throws: PreviewError.cellNeedsCellStage) { try options.request() }
    }

    @Test func yawAndPitchMakeOneViewAndDistanceAppliesToEach() throws {
        var options = PreviewOptions()
        options.mesh = "a.nif"
        options.yaw = 30
        options.distance = 400
        let custom = try options.request().views
        #expect(custom == [PreviewView(name: "custom", yaw: 30, pitch: 20, distance: 400)])
        options.angles = "front,top"
        let named = try options.request().views
        #expect(named.map(\.distance) == [400, 400])
    }

    @Test func coverageCountsPixelsApartFromTheMostCommonColour() {
        let grey: UInt32 = 0xFF30_3030
        let nearGrey: UInt32 = 0xFF33_3333
        let red: UInt32 = 0xFFFF_0000
        #expect(PreviewCoverage.fraction([grey, grey, nearGrey, grey]) == 0)
        #expect(PreviewCoverage.fraction([grey, grey, grey, red]) == 0.25)
        #expect(PreviewCoverage.fraction([]) == 0)
    }

    @Test func aBlankViewFailsTheReport() throws {
        let view = PreviewAngle.front.view
        let drawn = PreviewViewMeasure(
            view: view, distance: 300, drawCalls: 4, drawnInstances: 1, triangles: 120,
            coverage: 0.2
        )
        var blank = drawn
        blank.view = PreviewAngle.top.view
        blank.coverage = 0
        let request = try PreviewRequest(target: .mesh("a.nif")).validated()
        let report = PreviewReport(
            target: PreviewResolvedTarget(kind: "mesh"), stage: .studio, request: request,
            focus: ModelBounds(min: .zero, max: SIMD3(1, 1, 1)), failures: [],
            measures: [drawn, blank]
        )
        #expect(!report.passed)
        #expect(report.views.map(\.image) == ["front.png", "top.png"])
        let decoded = try JSONDecoder().decode(PreviewReport.self, from: report.json())
        #expect(decoded == report)
    }
}

struct PreviewSidebarOptionsTests {
    @Test func aCellTextIsAnEditorIDOrAGrid() throws {
        let interior = try PreviewOptions(kind: .cell, target: "WhiterunBanneredMare", inCell: "")
        #expect(interior.cell == "WhiterunBanneredMare")
        let exterior = try PreviewOptions(kind: .cell, target: "Tamriel 8 25", inCell: "")
        #expect(exterior.worldspace == "Tamriel")
        #expect((exterior.x, exterior.y) == (8, 25))
        #expect(throws: PreviewError.badGrid) {
            try PreviewOptions(kind: .cell, target: "Tamriel 8", inCell: "")
        }
    }

    @Test func aRecordTakesTheCellItStandsIn() throws {
        let options = try PreviewOptions(
            kind: .record, target: " HousecarlWhiterun ", inCell: "WhiterunBanneredMare"
        )
        #expect(options.record == "HousecarlWhiterun")
        #expect(try options.request().hostCell == .interiorCell("WhiterunBanneredMare"))
    }
}
