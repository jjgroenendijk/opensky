// The machine a benchmark ran on, so two results can be compared fairly.

import Darwin
import Foundation

nonisolated public struct BenchmarkMachine: Codable, Equatable, Sendable {
    /// `Mac15,9`, from `hw.model`.
    public let modelIdentifier: String
    /// `Apple M3 Max`, from `machdep.cpu.brand_string`.
    public let cpu: String
    public let gpu: String
    public let logicalCores: Int
    public let memoryGB: Double
    public let osVersion: String

    public init(
        modelIdentifier: String,
        cpu: String,
        gpu: String,
        logicalCores: Int,
        memoryGB: Double,
        osVersion: String
    ) {
        self.modelIdentifier = modelIdentifier
        self.cpu = cpu
        self.gpu = gpu
        self.logicalCores = logicalCores
        self.memoryGB = memoryGB
        self.osVersion = osVersion
    }

    /// - Parameter gpu: the Metal device name, which the caller already holds.
    public static func current(gpu: String) -> Self {
        let info = ProcessInfo.processInfo
        return Self(
            modelIdentifier: sysctlString("hw.model") ?? "unknown",
            cpu: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            gpu: gpu,
            logicalCores: info.processorCount,
            memoryGB: Double(info.physicalMemory) / 1_073_741_824,
            osVersion: info.operatingSystemVersionString
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: utf8, encoding: .utf8)
    }
}
