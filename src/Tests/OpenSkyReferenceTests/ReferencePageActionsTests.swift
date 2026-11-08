// The Reference Game page's export and import rules on a synthetic prefix.

import Foundation
@testable import OpenSkyReference
import Testing

struct ReferencePageActionsTests {
    private func makePrefix() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "reference-actions-\(UUID().uuidString)", directoryHint: .isDirectory)
        let prefix = ReferencePrefix(root: root)
        try FileManager.default.createDirectory(
            at: prefix.gameDirectory, withIntermediateDirectories: true
        )
        for file in [prefix.steamExecutable, prefix.gameExecutable] {
            try Data().write(to: file)
        }
        return root
    }

    private let view = ReferenceView(
        feet: SIMD3(1, 2, 3), yawDegrees: 0, pitchDegrees: 0, fovYDegrees: 65, gameHour: 12,
        place: .interior(editorID: "A"), weatherFormID: nil, firstPerson: true
    )

    @Test func exportWritesTheBatchFileIntoTheGameFolder() throws {
        let root = try makePrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        let notice = ReferencePageActions.exportView(view, prefix: root)
        #expect(!notice.isProblem)
        let file = ReferencePrefix(root: root).batchFile(named: "opensky")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.hasPrefix("coc A\r\n"))
        #expect(text.hasSuffix("tm\r\n"))
    }

    @Test func exportNeedsAPrefixAndARunningGame() throws {
        #expect(ReferencePageActions.exportView(view, prefix: nil).isProblem)
        let root = try makePrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ReferencePageActions.exportView(nil, prefix: root).isProblem)
    }

    @Test func importNamesTheMissingSave() throws {
        let root = try makePrefix()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ReferencePageActions.newestSave(prefix: root)
            == .failure(ReferenceNoticeError("The reference game has no save yet.")))
    }
}
