// Walks a NIF from its roots into `NIFEffectScene` nodes and unlit shapes.
// Skinned shapes and particle systems are not part of an effect scene.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated struct NIFEffectSceneBuilder {
    let file: NIFFile
    var nodes: [NIFEffectScene.Node] = []
    var shapes: [NIFEffectScene.Shape] = []

    private struct Visit {
        let ref: Int32
        let parent: Int?
        let depth: Int
    }

    mutating func walk(from root: Int32) throws {
        var stack = [Visit(ref: root, parent: nil, depth: 0)]
        var visited: Set<Int32> = []
        while let visit = stack.popLast() {
            guard visit.ref >= 0 else { continue }
            guard Int(visit.ref) < file.blocks.count else {
                throw NIFError.malformed("block ref \(visit.ref) out of range")
            }
            guard visit.depth <= NIFEffectScene.maxDepth, visited.insert(visit.ref).inserted else {
                throw NIFError.malformed("scene graph loops or nests too deep at \(visit.ref)")
            }
            let block = file.blocks[Int(visit.ref)]
            if Self.isNode(block.typeName) {
                let node = try NIFNode(data: block.data, header: file.header)
                let index = append(node.object, parent: visit.parent, billboard: billboard(block))
                // Reversed, so the stack pops children in file order.
                stack += node.children.reversed().map {
                    Visit(ref: $0, parent: index, depth: visit.depth + 1)
                }
            } else if NIFFile.Flattener.shapeTypes.contains(block.typeName) {
                try appendShape(block, parent: visit.parent)
            }
        }
    }

    static func isNode(_ type: String) -> Bool {
        NIFNode.traversedTypes.contains(type) || type == NIFEffectScene.billboardType
    }

    /// `NiBillboardNode` ends with its mode, after the `NiNode` fields.
    private func billboard(_ block: NIFFile.Block) -> UInt16? {
        guard block.typeName == NIFEffectScene.billboardType, block.data.count >= 2 else {
            return nil
        }
        let end = block.data.endIndex
        return UInt16(block.data[end - 2]) | UInt16(block.data[end - 1]) << 8
    }

    private mutating func append(
        _ object: NIFObjectPrefix, parent: Int?, billboard: UInt16?
    ) -> Int {
        nodes.append(NIFEffectScene.Node(
            name: object.name, parent: parent, translation: object.translation,
            rotation: simd_quatf(object.rotation), scale: object.scale,
            isHidden: object.isHidden, billboardMode: billboard
        ))
        return nodes.count - 1
    }

    private mutating func appendShape(_ block: NIFFile.Block, parent: Int?) throws {
        let shape: NIFTriShape = switch block.typeName {
        case "BSSubIndexTriShape":
            try NIFSubIndexTriShape(data: block.data, header: file.header).shape
        case "BSDynamicTriShape":
            try NIFDynamicTriShape(data: block.data, header: file.header).shape
        default:
            try NIFTriShape(data: block.data, header: file.header)
        }
        let node = append(shape.object, parent: parent, billboard: nil)
        guard shape.skinRef < 0, !shape.positions.isEmpty, !shape.indices.isEmpty else { return }
        let shaderBlock = shape.shaderPropertyRef >= 0 ? Int(shape.shaderPropertyRef) : nil
        try shapes.append(NIFEffectScene.Shape(
            node: node, positions: shape.positions,
            normals: shape.normals.count == shape.positions.count
                ? shape.normals : Array(repeating: .zero, count: shape.positions.count),
            uvs: shape.uvs.count == shape.positions.count
                ? shape.uvs : Array(repeating: .zero, count: shape.positions.count),
            colors: shape.colors.count == shape.positions.count
                ? shape.colors : Array(repeating: .one, count: shape.positions.count),
            indices: shape.indices,
            material: material(shader: shaderBlock, alpha: shape.alphaPropertyRef),
            shaderBlock: shaderBlock
        ))
    }

    private func material(shader: Int?, alpha alphaRef: Int32) throws -> NIFEffectMaterial {
        var material = NIFEffectMaterial()
        if alphaRef >= 0 {
            let block = try NIFParticleControllerDecoder.block(alphaRef, file)
            if block.typeName == "NiAlphaProperty" {
                let alpha = try NIFAlphaProperty(data: block.data, header: file.header)
                material.blend = alpha.blendEnabled
                    ? NIFBlend(
                        source: alpha.sourceBlendMode,
                        destination: alpha.destinationBlendMode
                    )
                    : nil
                material.alphaTest = alpha.testEnabled ? alpha.testThreshold : nil
            }
        }
        guard let shader else { return material }
        let block = try NIFParticleControllerDecoder.block(Int32(shader), file)
        switch block.typeName {
        case NIFFile.effectShaderType:
            let effect = try NIFEffectShaderProperty(data: block.data, header: file.header)
            material.sourceTexture = effect.sourceTexturePath
            material.shading = effect.shading
            material.uvOffset = effect.uvOffset
            material.uvScale = effect.uvScale
        case "BSLightingShaderProperty":
            let lit = try NIFLightingShaderProperty(data: block.data, header: file.header)
            material.uvOffset = lit.uvOffset
            material.uvScale = lit.uvScale
            material.shading.baseColor.w = lit.alpha
            if lit.textureSetRef >= 0 {
                let set = try NIFParticleControllerDecoder.block(lit.textureSetRef, file)
                material.sourceTexture = set.typeName == "BSShaderTextureSet"
                    ? try NIFShaderTextureSet(data: set.data, header: file.header).diffusePath
                    : nil
            }
        default:
            break
        }
        return material
    }
}
