// Collect particle systems from a parsed NIF. Walks the scene graph from the
// footer roots exactly like NIFModel: accumulate NiNode local transforms down
// the parent chain, cap depth, detect ref cycles with a path stack, range-check
// every block ref. NiParticleSystem / BSStripParticleSystem leaves are decoded
// into ParticleSystemDefinition with the accumulated world transform; their
// NiPSysData ref supplies capacity + atlas offsets, and each modifier ref is
// resolved to an emitter or modifier engine value. Unknown modifier types are
// noted as `.unsupported`; malformed bytes throw NIFError so the caller can
// skip the asset while the engine keeps running.
//
// Reference: NifTools nif.xml scene-graph semantics (NiNode children own the
// subtree; NiParticleSystem.Modifiers references the modifier chain).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// docs/formats/nif-particles.md "Scene graph -> particle system".

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
    func particleSystems() throws -> [ParticleSystemDefinition] {
        var walker = ParticleWalker(file: self)
        for root in roots {
            try walker.visit(ref: root, parent: matrix_identity_float4x4, depth: 0)
        }
        return walker.systems
    }

    fileprivate struct ParticleWalker {
        let file: NIFFile
        var systems: [ParticleSystemDefinition] = []
        /// Recursion stack for cycle detection; a set because legit graphs may
        /// reuse a subtree under two parents.
        var pathStack: Set<Int> = []

        mutating func visit(ref: Int32, parent: float4x4, depth: Int) throws {
            guard ref >= 0 else { return } // -1 = null ref
            let index = Int(ref)
            guard index < file.blocks.count else {
                throw NIFError.malformed(
                    "block ref \(ref) out of range (\(file.blocks.count) blocks)"
                )
            }
            guard depth <= NIFFile.maxParticleGraphDepth else {
                throw NIFError.malformed(
                    "scene graph deeper than \(NIFFile.maxParticleGraphDepth)"
                )
            }
            guard pathStack.insert(index).inserted else {
                throw NIFError.malformed("scene graph cycle at block \(index)")
            }
            defer { pathStack.remove(index) }

            let block = file.blocks[index]
            if NIFNode.traversedTypes.contains(block.typeName) {
                let node = try NIFNode(data: block.data, header: file.header)
                let world = parent * node.object.localTransform
                for child in node.children {
                    try visit(ref: child, parent: world, depth: depth + 1)
                }
            } else if NIFFile.particleSystemTypes.contains(block.typeName) {
                try systems.append(decodeSystem(block: block, parent: parent))
            }
            // Any other type is a leaf we do not collect (geometry, shader
            // properties, controllers…): subtree ends.
        }

        private func decodeSystem(
            block: NIFFile.Block,
            parent: float4x4
        ) throws -> ParticleSystemDefinition {
            let system = try NIFParticleSystem(data: block.data, header: file.header)
            let data = try decodeData(ref: system.dataRef)
            var emitters: [ParticleEmitter] = []
            var modifiers: [ParticleModifier] = []
            for ref in system.modifierRefs {
                guard ref >= 0 else { continue } // -1 = empty chain slot
                let modBlock = try self.block(at: Int(ref))
                if NIFParticleModifierDecoder.isEmitter(modBlock.typeName) {
                    try emitters.append(NIFParticleModifierDecoder.emitter(
                        typeName: modBlock.typeName,
                        data: modBlock.data,
                        header: file.header
                    ))
                } else {
                    try modifiers.append(NIFParticleModifierDecoder.modifier(
                        typeName: modBlock.typeName,
                        data: modBlock.data,
                        header: file.header
                    ))
                }
            }
            return ParticleSystemDefinition(
                name: system.object.name,
                worldTransform: parent * system.object.localTransform,
                worldSpace: system.worldSpace,
                maxParticles: data?.maxParticles ?? 0,
                emitters: emitters,
                modifiers: modifiers,
                subtextureOffsets: data?.subtextureOffsets ?? [],
                shaderPropertyRef: system.shaderPropertyRef,
                alphaPropertyRef: system.alphaPropertyRef
            )
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
