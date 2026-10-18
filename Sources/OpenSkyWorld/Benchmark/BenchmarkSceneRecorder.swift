// Collects one scene's measured frames and turns them into its result.

import Foundation
import OpenSkyRendering

nonisolated struct BenchmarkSceneRecorder {
    private(set) var frameMS: [Double] = []
    private(set) var gpuMS: [Double] = []
    private var passMS: [GPUPass: [Double]] = [:]
    private var cpuMS: [BenchmarkCPUProbe: [Double]] = [:]
    private var drawCalls = 0
    private var drawnInstances = 0
    private var memory = GPUMemoryTracker()

    mutating func add(frameMS interval: Double, sample: BenchmarkFrameSample) {
        frameMS.append(interval)
        for (probe, value) in sample.cpuMS {
            cpuMS[probe, default: []].append(value)
        }
        drawCalls += sample.drawCalls
        drawnInstances += sample.drawnInstances
    }

    mutating func add(gpuMS spans: [Double], passes: [[GPUPass: Double]]) {
        gpuMS += spans
        for frame in passes {
            for (pass, value) in frame {
                passMS[pass, default: []].append(value)
            }
        }
    }

    mutating func add(memory usage: GPUMemoryUsage) {
        memory.add(usage)
    }

    var gpuMemory: BenchmarkGPUMemory? {
        memory.result
    }

    func fill(_ result: inout BenchmarkSceneResult) {
        result.frameTime = BenchmarkDistribution(milliseconds: frameMS)
        result.gpuTime = BenchmarkDistribution(milliseconds: gpuMS)
        result.passes = Dictionary(uniqueKeysWithValues: passMS.compactMap { pass, values in
            BenchmarkSpread(milliseconds: values).map { (pass.rawValue, $0) }
        })
        result.cpu = Dictionary(uniqueKeysWithValues: cpuMS.compactMap { probe, values in
            BenchmarkSpread(milliseconds: values).map { (probe.rawValue, $0) }
        })
        if !frameMS.isEmpty {
            result.averageDrawCalls = drawCalls / frameMS.count
            result.averageDrawnInstances = drawnInstances / frameMS.count
        }
        result.gpuMemory = memory.result
    }
}
