// The trap test cell `WarehouseTraps` with the install's own scripts: a pressure plate
// fires its trap chain, crossing a tripwire spends it, the use key reaches the
// plate's script, and a HAZD hits the player. Only counts, editor IDs, and script
// state names go to `logs/`.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
@testable import OpenSkyWorldState
import TagsTesting
import Testing

@Suite(.tags(.gpu))
@MainActor
struct TrapCellRealDataTests {
    static let cell = FormID(0x0002_43DF)
    static let cellEditorID = "WarehouseTraps"

    @Test(.enabled(if: RealDataEnvironment.canRender))
    func pressurePlateTripwireAndHazardRunInTheTrapCell() throws {
        let session = try TrapCellSession.make()
        var report = ["cell\t\(Self.cellEditorID)"] + session.summaryLines

        let plate = try #require(session.scripted("pressureplate").first)
        let fired = session.cross(plate, script: "pressureplate", label: "plate")
        report += fired.lines
        #expect(fired.before == "Inactive")
        #expect(fired.queued > 0)
        #expect(fired.inside != "Inactive", "stepping on the plate left it armed")
        #expect(fired.activateChildren > 0, "the plate names no trap through XAPR")
        // The plate's own activation, then one per activate child.
        #expect(
            fired.newDeltas >= 1 + fired.activateChildren,
            "the plate's activation stopped short"
        )

        let tripwire = try #require(session.scripted("tripwire").first)
        let tripped = session.cross(tripwire, script: "tripwire", label: "tripwire")
        report += tripped.lines
        #expect(tripped.before == "Inactive")
        #expect(tripped.inside != "Inactive", "crossing the wire left it armed")

        let pressed = session.press(plate)
        report.append("use-key events on the plate\t\(pressed)")
        #expect(pressed > 0)

        let hit = try session.hazardHit()
        report += hit.lines
        #expect(hit.targets == [.player])
        #expect(hit.storedEffects > 0)

        let tally = session.world.runtime.tally
        report += [
            "faults\t\(tally.faultTotal)",
            "unknown native calls\t\(tally.unimplementedNativeTotal)",
            "stubbed native calls\t\(tally.stubbedNativeTotal)"
        ]
        report += tally.rankedUnimplementedNatives.map { "unknown native\t\($0.name) \($0.count)" }
        report += tally.rankedNativeFailures.map { "native failure\t\($0.name) \($0.count)" }
        report += tally.rankedFaultKinds.map { "fault kind\t\($0.name) \($0.count)" }
        report += tally.faults.prefix(12).map { "fault\t\($0)" }
        #expect(tally.unimplementedNativeTotal == 0)
        try write(report)
    }

    private func write(_ lines: [String]) throws {
        let directory = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(
            to: directory.appending(path: "trap-cell.log"), atomically: true, encoding: .utf8
        )
        print(lines.joined(separator: "\n"))
    }
}
