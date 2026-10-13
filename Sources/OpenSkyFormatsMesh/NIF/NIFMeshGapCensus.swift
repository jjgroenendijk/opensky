// What the meshes of an install ask for that the engine does not read: block types no
// code names, shader types and flags no draw term uses, and decode failures. Names and
// counts only.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFMeshGapCensus: Sendable {
    public private(set) var fileCount = 0
    /// Block type -> blocks.
    public private(set) var blockTypes = GapCounts()
    /// Lighting shader type name -> lighting shader blocks.
    public private(set) var lightingTypes = GapCounts()
    /// Shader flag name -> shader blocks that set it.
    public private(set) var lightingFlags = GapCounts()
    public private(set) var effectFlags = GapCounts()
    /// Failure kind -> files that hit it.
    public private(set) var failures = GapCounts()

    public init() {}

    public static let readLightingTypes = Set(
        NIFLightingShaderType.engineRead.map(NIFLightingShaderType.name)
    )
    public static let readLightingFlags = Set(NIFShaderFlag.lightingRead.map(\.name))
    public static let readEffectFlags = Set(NIFShaderFlag.effectRead.map(\.name))

    public mutating func record(data: Data) {
        fileCount += 1
        let file: NIFFile
        do {
            file = try NIFFile(data: data)
        } catch {
            noteFailure("file does not open", error)
            return
        }
        var kinds: Set<String> = []
        for block in file.blocks {
            blockTypes.add(block.typeName)
            recordShader(block, header: file.header, failures: &kinds)
        }
        recordDecoders(file, failures: &kinds)
        for kind in kinds {
            failures.add(kind)
        }
    }

    private mutating func recordShader(
        _ block: NIFFile.Block,
        header: NIFHeader,
        failures kinds: inout Set<String>
    ) {
        do {
            if block.typeName == "BSLightingShaderProperty" {
                let shader = try NIFLightingShaderProperty(data: block.data, header: header)
                lightingTypes.add(NIFLightingShaderType.name(shader.shaderType))
                for flag in NIFShaderFlag.set(in: shader.shaderFlags1, shader.shaderFlags2) {
                    lightingFlags.add(flag.name)
                }
            } else if block.typeName == NIFFile.effectShaderType {
                let shader = try NIFEffectShaderProperty(data: block.data, header: header)
                for flag in NIFShaderFlag.set(in: shader.shaderFlags1, shader.shaderFlags2) {
                    effectFlags.add(flag.name)
                }
            }
        } catch {
            kinds.insert(Self.kind("\(block.typeName) does not decode", error))
        }
    }

    private func recordDecoders(_ file: NIFFile, failures kinds: inout Set<String>) {
        do {
            _ = try file.model()
        } catch {
            kinds.insert(Self.kind("model does not build", error))
        }
        do {
            for system in try file.particleSystems() {
                for case let .unsupported(type) in system.modifiers.map(\.kind) {
                    kinds.insert("particle modifier not modelled: \(type)")
                }
            }
        } catch {
            kinds.insert(Self.kind("particles do not decode", error))
        }
        for failure in file.collisionModel().decodeFailures {
            kinds.insert("collision does not decode: " + GapCounts.failureKind(failure.message))
        }
        do {
            _ = try file.sequences()
        } catch {
            kinds.insert(Self.kind("animation sequences do not decode", error))
        }
    }

    private mutating func noteFailure(_ what: String, _ error: any Error) {
        failures.add(Self.kind(what, error))
    }

    private static func kind(_ what: String, _ error: any Error) -> String {
        "\(what): " + GapCounts.failureKind(String(describing: error))
    }
}
