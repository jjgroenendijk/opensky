// Collects particle systems from a parsed NIF, walking the graph like
// NIFModel. Unknown modifier types become `.unsupported`; malformed bytes
// throw `NIFError`. See docs/formats/nif-particles.md.

import Foundation
import simd

nonisolated extension NIFFile {
    /// Same depth cap as NIFModel: vanilla nests a handful of levels; deeper
    /// is malformed or hostile.
    private static let maxParticleGraphDepth = 64

    private static let particleSystemTypes: Set = [
        "NiParticleSystem", "BSStripParticleSystem"
    ]

    /// Flattens the block tree into the particle systems it contains, each in
    /// model space. Non-particle leaves are skipped; a malformed system throws.
    public func particleSystems() throws -> [ParticleSystemDefinition] {
        var walker = ParticleWalker(file: self)
        for root in roots {
            try walker.walk(from: root)
        }
        return try walker.found.map { try walker.decodeSystem(block: $0.block, parent: $0.parent) }
    }

    fileprivate struct ParticleWalker {
        let file: NIFFile
        /// Systems in walk order. They decode after the walk, because a mesh
        /// emitter needs the transform of a shape found later.
        var found: [(block: NIFFile.Block, parent: float4x4)] = []
        /// The parent transform of every block the walk reached.
        var parents: [Int: float4x4] = [:]

        mutating func walk(from root: Int32) throws {
            var stack = NIFGraphStack(root: root)
            while let visit = stack.next() {
                guard visit.ref >= 0 else { continue } // -1 = null ref
                let index = Int(visit.ref)
                guard index < file.blocks.count else {
                    throw NIFError.malformed(
                        "block ref \(visit.ref) out of range (\(file.blocks.count) blocks)"
                    )
                }
                guard visit.depth <= NIFFile.maxParticleGraphDepth else {
                    throw NIFError.malformed(
                        "scene graph deeper than \(NIFFile.maxParticleGraphDepth)"
                    )
                }
                guard stack.enter(index) else {
                    throw NIFError.malformed("scene graph cycle at block \(index)")
                }

                let block = file.blocks[index]
                parents[index] = parents[index] ?? visit.parent
                if NIFNode.traversedTypes.contains(block.typeName) {
                    let node = try NIFNode(data: block.data, header: file.header)
                    let world = visit.parent * node.object.localTransform
                    stack.push(
                        children: node.children,
                        parent: world,
                        depth: visit.depth + 1
                    )
                } else if NIFFile.particleSystemTypes.contains(block.typeName) {
                    found.append((block, visit.parent))
                }
                // Any other type is a leaf we do not collect (geometry, shader
                // properties, controllers…): subtree ends.
            }
        }

        func decodeSystem(
            block: NIFFile.Block,
            parent: float4x4
        ) throws -> ParticleSystemDefinition {
            let system = try NIFParticleSystem(data: block.data, header: file.header)
            let systemTransform = parent * system.object.localTransform
            let data = try decodeData(ref: system.dataRef)
            var emitters: [ParticleEmitter] = []
            var modifiers: [ParticleModifier] = []
            for ref in system.modifierRefs {
                guard ref >= 0 else { continue } // -1 = empty chain slot
                let modBlock = try self.block(at: Int(ref))
                if NIFParticleModifierDecoder.isEmitter(modBlock.typeName) {
                    let emitter = try NIFParticleModifierDecoder.emitter(
                        typeName: modBlock.typeName,
                        data: modBlock.data,
                        header: file.header
                    )
                    try emitters.append(withMeshGeometry(emitter, systemTransform: systemTransform))
                } else {
                    try modifiers.append(NIFParticleModifierDecoder.modifier(
                        typeName: modBlock.typeName,
                        data: modBlock.data,
                        header: file.header
                    ))
                }
            }
            return try ParticleSystemDefinition(
                name: system.object.name,
                worldTransform: systemTransform,
                worldSpace: system.worldSpace,
                maxParticles: data?.maxParticles ?? 0,
                emitters: emitters,
                modifiers: modifiers,
                subtextureOffsets: data?.subtextureOffsets ?? [],
                shaderPropertyRef: system.shaderPropertyRef,
                alphaPropertyRef: system.alphaPropertyRef,
                effectShader: effectShader(ref: system.shaderPropertyRef),
                alphaProperty: alphaProperty(ref: system.alphaPropertyRef),
                emitterControllers: NIFParticleControllerDecoder.emitterControllers(
                    from: system.object.controllerRef, file: file
                )
            )
        }

        /// Fills a mesh emitter with its shapes' geometry in the system's space.
        private func withMeshGeometry(
            _ emitter: ParticleEmitter,
            systemTransform: float4x4
        ) throws -> ParticleEmitter {
            guard case var .mesh(source) = emitter.shape else { return emitter }
            let toSystem = systemTransform.inverse
            for ref in source.meshRefs where ref >= 0 {
                let index = Int(ref)
                guard let shape = try NIFMeshEmitterGeometry.shape(try block(at: index), file)
                else { continue }
                let local = toSystem * (parents[index] ?? matrix_identity_float4x4)
                    * shape.object.localTransform
                NIFMeshEmitterGeometry.append(shape, transform: local, to: &source)
            }
            return emitter.replacingShape(.mesh(source))
        }

        /// Resolves the shader ref when it is a BSEffectShaderProperty. Other
        /// shader types (e.g. BSLightingShaderProperty on a lit particle
        /// shape) yield nil — legitimate content, same discipline as
        /// NIFModel.resolveMaterial's fallback. Out-of-range refs throw.
        private func effectShader(ref: Int32) throws -> NIFEffectShaderProperty? {
            guard ref >= 0 else { return nil }
            let shaderBlock = try block(at: Int(ref))
            guard shaderBlock.typeName == "BSEffectShaderProperty" else { return nil }
            return try NIFEffectShaderProperty(
                data: shaderBlock.data,
                header: file.header
            )
        }

        /// Resolves the alpha ref when it is a NiAlphaProperty; nil otherwise.
        private func alphaProperty(ref: Int32) throws -> NIFAlphaProperty? {
            guard ref >= 0 else { return nil }
            let alphaBlock = try block(at: Int(ref))
            guard alphaBlock.typeName == "NiAlphaProperty" else { return nil }
            return try NIFAlphaProperty(data: alphaBlock.data, header: file.header)
        }

        /// Resolves the NiPSysData ref; nil ref -> no capacity. A ref to a
        /// non-data block is malformed, same discipline as the walk.
        private func decodeData(ref: Int32) throws -> NIFParticleData? {
            guard ref >= 0 else { return nil }
            let dataBlock = try block(at: Int(ref))
            switch dataBlock.typeName {
            case "NiPSysData":
                return try NIFParticleData(data: dataBlock.data, header: file.header)
            case "BSStripPSysData":
                return try NIFParticleData(
                    data: dataBlock.data,
                    header: file.header,
                    isStrip: true
                )
            default:
                throw NIFError.malformed(
                    "particle data ref \(ref) is \(dataBlock.typeName), not NiPSysData"
                )
            }
        }

        private func block(at index: Int) throws -> NIFFile.Block {
            guard index >= 0, index < file.blocks.count else {
                throw NIFError.malformed(
                    "block ref \(index) out of range (\(file.blocks.count) blocks)"
                )
            }
            return file.blocks[index]
        }
    }
}
