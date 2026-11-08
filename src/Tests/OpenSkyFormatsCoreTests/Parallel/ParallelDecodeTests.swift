// The fan-out must return every result, whether it runs in parallel or serially.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
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

    @Test func orderedMapKeepsTheInputOrderAcrossChunks() {
        let values = ParallelDecode.mapInOrder(Array(0 ..< 1000), chunkSize: 7) { $0 * 3 }
        #expect(values == (0 ..< 1000).map { $0 * 3 })
        #expect(ParallelDecode.mapInOrder([Int](), chunkSize: 7) { $0 }.isEmpty)
    }
}
