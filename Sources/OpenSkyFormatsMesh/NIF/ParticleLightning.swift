// The lightning bolt a `BSProceduralLightningController` builds on its empty shape. The
// fields are nif.xml's; how the bolt is grown from them is OpenSky's reading
// (docs/rendering/particles.md#ribbons).

import Foundation
import OpenSkyFormatsCore
import simd

/// The bolt parameters of one lightning controller.
nonisolated public struct ParticleLightning: Equatable, Sendable {
    /// Times the bolt is halved and bent; nif.xml allows 0 to 12.
    public var subdivisions: Int
    public var branches: Int
    public var branchVariation: Int
    /// Units along the shape's +Y.
    public var length: Float
    public var lengthVariation: Float
    public var width: Float
    public var childWidthMultiplier: Float
    /// How far the bolt bends sideways; 0 is straight.
    public var arcOffset: Float
    public var fadesMainBolt: Bool
    public var fadesChildBolts: Bool
    public var animatesArcOffset: Bool

    public init(_ controller: NIFLightningController) {
        subdivisions = Int(min(controller.subdivisions, 12))
        branches = Int(min(controller.branches, 10))
        branchVariation = Int(min(controller.branchVariation, 10))
        length = controller.length.isFinite ? max(controller.length, 0) : 0
        lengthVariation = controller.lengthVariation.isFinite ? controller.lengthVariation : 0
        width = controller.width.isFinite ? max(controller.width, 0) : 0
        childWidthMultiplier = controller.childWidthMultiplier.isFinite
            ? controller.childWidthMultiplier : 0
        arcOffset = controller.arcOffset.isFinite ? controller.arcOffset : 0
        fadesMainBolt = controller.fadesMainBolt
        fadesChildBolts = controller.fadesChildBolts
        animatesArcOffset = controller.animatesArcOffset
    }
}

nonisolated extension NIFFile {
    /// One definition per lightning controller whose target shape the scene reaches, at
    /// that shape's place in the model. Its effect shader is the controller's own.
    public func lightningSystems() -> [ParticleSystemDefinition] {
        let parents = nodeParents()
        return blocks.compactMap { block in
            guard
                let controller = Self.lightningController(block),
                controller.base.targetRef >= 0, Int(controller.base.targetRef) < blocks.count
            else { return nil }
            let target = Int(controller.base.targetRef)
            guard let transform = modelTransform(of: target, parents: parents) else { return nil }
            let shape = try? NIFTriShape.decode(blocks[target], in: self)
            var system = ParticleSystemDefinition(
                name: shape?.object.name, worldTransform: transform, worldSpace: false,
                maxParticles: 0, emitters: [], modifiers: [], subtextureOffsets: [],
                shaderPropertyRef: controller.shaderPropertyRef,
                alphaPropertyRef: shape?.alphaPropertyRef ?? -1,
                effectShader: effectShader(at: controller.shaderPropertyRef),
                alphaProperty: alphaProperty(at: shape?.alphaPropertyRef ?? -1)
            )
            system.lightning = ParticleLightning(controller)
            system.ancestorNodes = nodeNames(above: target, parents: parents)
            return system
        }
    }

    private static func lightningController(_ block: Block) -> NIFLightningController? {
        guard block.typeName == NIFLightningController.typeName else { return nil }
        var reader = BinaryReader(block.data)
        return try? NIFLightningController(reader: &reader)
    }

    /// The block's transform in the model, composed up its parents. Nil for a block no
    /// root reaches. The step limit stops a cyclic file.
    private func modelTransform(of block: Int, parents: [Int: Int]) -> float4x4? {
        var transform = matrix_identity_float4x4
        var current: Int? = block
        var steps = 0
        while let index = current, steps < 64 {
            var reader = BinaryReader(blocks[index].data)
            guard let object = try? NIFObjectPrefix(reader: &reader, header: header) else {
                return nil
            }
            guard let parent = parents[index] else {
                // A root: the walk drops a placed root's own transform.
                return walkParent(ofRoot: Int32(index)) * object.localTransform * transform
            }
            transform = object.localTransform * transform
            current = parent
            steps += 1
        }
        return nil
    }

    private func effectShader(at ref: Int32) -> NIFEffectShaderProperty? {
        guard
            ref >= 0, Int(ref) < blocks.count,
            blocks[Int(ref)].typeName == "BSEffectShaderProperty"
        else { return nil }
        return try? NIFEffectShaderProperty(data: blocks[Int(ref)].data, header: header)
    }

    private func alphaProperty(at ref: Int32) -> NIFAlphaProperty? {
        guard ref >= 0, Int(ref) < blocks.count, blocks[Int(ref)].typeName == "NiAlphaProperty"
        else { return nil }
        return try? NIFAlphaProperty(data: blocks[Int(ref)].data, header: header)
    }
}
