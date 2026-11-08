// Pins the SplitMix64 stream, so every seeded roll in the engine stays the same.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SplitMix64Tests {
    @Test func seedZeroMatchesTheReferenceStream() {
        var random = SplitMix64(seed: 0)
        #expect(random.next() == 0xE220_A839_7B1D_CDAF)
        #expect(random.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(random.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func unitFloatUsesTheTopBits() {
        var random = SplitMix64(seed: 0)
        let value = random.unitFloat()
        #expect(value == Float(0xE220_A839_7B1D_CDAF as UInt64 >> 40) / Float(1 << 24))
        #expect((0 ..< 1).contains(value))
    }

    @Test func boundedDrawStaysInRangeAndRepeats() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        for _ in 0 ..< 64 {
            let value = first.next(upperBound: 7)
            #expect(value < 7)
            #expect(value == second.next(upperBound: 7))
        }
        #expect(first.next(upperBound: 1) == 0)
    }
}
