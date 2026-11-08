@testable import OpenSkyRendering
import Testing

struct GPUFramePartsTests {
    @Test func partsAddUpOnceAllReport() {
        let parts = GPUFrameParts(count: 2)
        #expect(parts.add(start: 10, end: 10.004) == nil)
        let busy = parts.add(start: 10.005, end: 10.011)
        #expect(abs((busy ?? 0) - 0.010) < 1e-9)
    }

    /// A buffer the GPU did not run reports a zero start; its end alone is not busy time.
    @Test func aZeroStartAddsNoTime() {
        let parts = GPUFrameParts(count: 2)
        #expect(parts.add(start: 0, end: 300_000) == nil)
        let busy = parts.add(start: 10, end: 10.002)
        #expect(abs((busy ?? 0) - 0.002) < 1e-9)
    }
}
