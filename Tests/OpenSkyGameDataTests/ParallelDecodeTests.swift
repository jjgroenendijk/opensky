// The fan-out must return every result, whether it runs in parallel or serially.

@testable import OpenSkyGameData
import Testing

struct ParallelDecodeTests {
    @Test func parallelMapKeepsEveryResult() {
        let values = ParallelDecode.map(0 ..< 100) { $0.isMultiple(of: 3) ? nil : $0 * 2 }
        #expect(values.count == 66)
        #expect(values[50] == 100)
        #expect(values[3] == nil)
    }

    @Test func fewItemsRunSeriallyWithTheSameResult() {
        let values = ParallelDecode.map(["a", "b"]) { $0 + "!" }
        #expect(values == ["a": "a!", "b": "b!"])
    }
}
