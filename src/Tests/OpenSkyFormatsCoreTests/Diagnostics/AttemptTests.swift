import Foundation
import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct AttemptTests {
    private struct Failure: Error {}

    private func value(_ number: Int) throws -> Int {
        guard number >= 0 else { throw Failure() }
        return number
    }

    private func optional(_ number: Int) throws -> Int? {
        guard number >= 0 else { throw Failure() }
        return number == 0 ? nil : number
    }

    @Test func aCallThatSucceedsGivesItsValue() {
        let result = attempt { try value(3) }
        #expect(result == 3)
    }

    @Test func aCallThatThrowsGivesNil() {
        let result = attempt { try value(-1) }
        #expect(result == nil)
    }

    @Test func anOptionalResultIsNotNested() {
        let none = attempt { try optional(0) }
        let failed = attempt { try optional(-1) }
        let some = attempt { try optional(2) }
        #expect(none == nil)
        #expect(failed == nil)
        #expect(some == 2)
    }

    @Test func anAsyncCallThatThrowsGivesNil() async {
        let result = await attempt { () async throws -> Int in
            try value(-1)
        }
        #expect(result == nil)
    }
}

@Suite(.tags(.parser))
struct AttemptIfPresentTests {
    @Test func aMissingFileGivesNil() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-no-such-\(UUID())")
        let bytes = attemptIfPresent { try Data(contentsOf: url) }
        #expect(bytes == nil)
    }

    @Test func aPresentFileGivesItsBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-attempt-\(UUID())")
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = attemptIfPresent { try Data(contentsOf: url) }
        #expect(bytes == Data([1, 2, 3]))
    }
}
