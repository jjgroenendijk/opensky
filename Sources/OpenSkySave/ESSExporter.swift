// Turns the contents of an OpenSky save into a Skyrim SE `.ess`: the reverse of the
// import mapping. It is pure, so the same contents and plugins give the same bytes.
// Each part that has no place in the save is counted with its reason.
// See docs/engine/ess-export.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyWorldState

nonisolated public struct ESSExportResult: Sendable {
    public let data: Data
    public let report: ESSExportReport
}

nonisolated public struct ESSExporter {
    let contents: OpenSkySaveContents
    let records: any ESSExportRecords
    let header: ESSExportHeader
    var forms: ESSExportForms
    var report = ESSExportReport()
    /// Reference changes by key, written in key order at the end.
    var references: [ReferenceKey: ESSReferenceChange] = [:]
    var aliasFills: [ReferenceKey: [ESSAliasInstance]] = [:]
    var changeForms: [ESSChangeForm] = []
    var globals: [ESSGlobalVariable] = []
    var papyrus = ESSPapyrusWriter()
    var location: ESSPlayerLocation?
    var visitedWorldspaces: [UInt32] = []
    /// Where exterior created references go, since OpenSky keeps no worldspace for them.
    var playerWorldspace: ESSRefID?

    public static func run(
        _ contents: OpenSkySaveContents, records: any ESSExportRecords, header: ESSExportHeader
    ) throws(ESSExportError) -> ESSExportResult {
        var exporter = try ESSExporter(contents: contents, records: records, header: header)
        try exporter.exportPlayer()
        try exporter.exportEntries()
        exporter.exportGlobals()
        exporter.exportScripts()
        return try exporter.finish()
    }

    init(
        contents: OpenSkySaveContents, records: any ESSExportRecords, header: ESSExportHeader
    ) throws(ESSExportError) {
        self.contents = contents
        self.records = records
        self.header = header
        forms = try ESSExportForms(records.plugins)
    }

    /// Wraps a format error, which only a value the format cannot hold raises.
    static func encode<Value>(
        _ body: () throws(ESSError) -> Value
    ) throws(ESSExportError) -> Value {
        do {
            return try body()
        } catch {
            throw .format(error)
        }
    }

    // MARK: - Globals and clock

    mutating func exportGlobals() {
        var written: Set<ESSRefID> = []
        for entry in contents.snapshot.globals {
            guard let ref = forms.ref(entry.key) else {
                report.update("globals") { $0.drop("global from a plugin not loaded") }
                continue
            }
            written.insert(ref)
            globals.append(ESSGlobalVariable(global: ref, value: entry.value.value))
            report.update("globals") { $0.written += 1 }
        }
        guard let clock = contents.clock else {
            report.update("clock") { $0.drop("no game clock in the save") }
            return
        }
        for time in GameClock.TimeGlobal.allCases {
            guard
                let form = records.form(editorID: time.editorID, signature: "GLOB"),
                let ref = forms.ref(form), !written.contains(ref)
            else {
                report.update("clock") { $0.drop("\(time.editorID) global not found") }
                continue
            }
            globals.append(ESSGlobalVariable(global: ref, value: clock.projectedValue(time)))
            report.update("clock") { $0.written += 1 }
        }
    }

    // MARK: - Result

    func finish() throws(ESSExportError) -> ESSExportResult {
        var references = changeForms
        for key in self.references.keys.sorted() {
            guard let change = self.references[key] else { continue }
            try references.append(Self.encode { () throws(ESSError) in try change.changeForm() })
        }
        let file = try Self.encode { () throws(ESSError) in try fileContents(references) }
        let data = try Self.encode { () throws(ESSError) in try file.encoded() }
        return ESSExportResult(data: data, report: report)
    }

    private func fileContents(_ changeForms: [ESSChangeForm]) throws(ESSError) -> ESSFileContents {
        var table1 = try ESSGlobalData.group1Types.map(ESSGlobalData.empty)
        var table3 = try ESSGlobalData.group3Types.map(ESSGlobalData.empty)
        let empty = ESSPlayerLocation(
            nextObjectID: 0, worldspace: ESSRefID(raw: 0), cell: .zero,
            space: ESSRefID(raw: 0), position: .zero
        )
        let nextObject = UInt32(clamping: contents.snapshot.nextGeneratedSequence)
        let place = location ?? empty
        table1[1] = try ESSPlayerLocation(
            nextObjectID: nextObject, worldspace: place.worldspace, cell: place.cell,
            space: place.space, position: place.position
        ).table()
        table1[3] = try ESSGlobalVariable.table(globals)
        if let clock = contents.clock {
            let null = ESSRefID(raw: 0)
            table1[6] = try ESSWeather(
                climate: null, weather: null, previousWeather: null, regionWeather: null,
                currentHour: clock.hourOfDay, transition: 1
            ).table()
        }
        table3[1] = try papyrus.table()
        let picture = screenshot()
        return try ESSFileContents(
            header: fileHeader(picture), screenshot: picture, plugins: forms.plugins,
            lightPlugins: forms.lightPlugins, globalData1: table1,
            globalData2: ESSGlobalData.group2Types.map(ESSGlobalData.empty),
            changeForms: changeForms, globalData3: table3, formIDArray: forms.formIDArray,
            visitedWorldspaces: visitedWorldspaces
        )
    }

    /// The save's thumbnail, or one black pixel for a save that has none.
    private func screenshot() -> ESSScreenshot {
        guard let thumbnail = contents.thumbnail else {
            return ESSScreenshot(width: 1, height: 1, rgba: Data([0, 0, 0, 0xFF]))
        }
        return ESSScreenshot(width: thumbnail.width, height: thumbnail.height, rgba: thumbnail.rgba)
    }
}
