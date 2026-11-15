// The lightning bolt a `BSProceduralLightningController` builds on the empty shape below
// its node. The fields are nif.xml's; how the bolt grows from them is on
// docs/rendering/particles.md#lightning.

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
    /// With it, the arc offset track bends a standing bolt; without it only a new bolt
    /// takes a new arc offset.
    public var animatesArcOffset: Bool
    /// The tracks the default sequence feeds; nil when nothing keys the controller.
    public var tracks: LightningTracks?
    /// The tracks of each sequence that feeds the controller, by lowercased name.
    public var sequenceTracks: [String: LightningTracks] = [:]

    /// True when a generation track can show a bolt. Without one nothing is drawn.
    public var isKeyed: Bool {
        tracks?.generation.isEmpty == false
            || sequenceTracks.values.contains { !$0.generation.isEmpty }
    }

    public init(
        subdivisions: Int = 0, branches: Int = 0, branchVariation: Int = 0, length: Float = 0,
        lengthVariation: Float = 0, width: Float = 0, childWidthMultiplier: Float = 1,
        arcOffset: Float = 0, fadesMainBolt: Bool = false, fadesChildBolts: Bool = false,
        animatesArcOffset: Bool = false
    ) {
        self.subdivisions = subdivisions
        self.branches = branches
        self.branchVariation = branchVariation
        self.length = length
        self.lengthVariation = lengthVariation
        self.width = width
        self.childWidthMultiplier = childWidthMultiplier
        self.arcOffset = arcOffset
        self.fadesMainBolt = fadesMainBolt
        self.fadesChildBolts = fadesChildBolts
        self.animatesArcOffset = animatesArcOffset
    }

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

    /// Replaces each field a track keys with the track's value at `time`.
    public mutating func apply(_ tracks: LightningTracks, at time: Float) {
        let count = { (keys: [NIFKey<Float>], limit: Int) -> Int? in
            NIFKeySampler.float(keys, at: time).map { value in
                value.isFinite ? min(max(Int(value.rounded()), 0), limit) : 0
            }
        }
        let number = { (keys: [NIFKey<Float>]) -> Float? in
            NIFKeySampler.float(keys, at: time).flatMap { $0.isFinite ? $0 : nil }
        }
        subdivisions = count(tracks.subdivisions, 12) ?? subdivisions
        branches = count(tracks.branches, 10) ?? branches
        branchVariation = count(tracks.branchVariation, 10) ?? branchVariation
        length = number(tracks.length).map { max($0, 0) } ?? length
        lengthVariation = number(tracks.lengthVariation) ?? lengthVariation
        width = number(tracks.width).map { max($0, 0) } ?? width
        if animatesArcOffset {
            arcOffset = number(tracks.arcOffset) ?? arcOffset
        }
    }
}

/// The keys a sequence, or the controller's own interpolators, give a lightning
/// controller. An empty track leaves the controller's stored field in use.
nonisolated public struct LightningTracks: Equatable, Sendable {
    public var timing: ControllerTiming
    /// The bolt shows while this is on; each change to on grows a new bolt.
    public var generation: [NIFKey<Bool>] = []
    /// Each change gives the standing bolt new lengths and bends.
    public var mutation: [NIFKey<Bool>] = []
    public var subdivisions: [NIFKey<Float>] = []
    public var branches: [NIFKey<Float>] = []
    public var branchVariation: [NIFKey<Float>] = []
    public var length: [NIFKey<Float>] = []
    public var lengthVariation: [NIFKey<Float>] = []
    public var width: [NIFKey<Float>] = []
    public var arcOffset: [NIFKey<Float>] = []

    public init(timing: ControllerTiming) {
        self.timing = timing
    }
}

nonisolated extension NIFFile {
    /// One definition per lightning controller whose node the scene reaches, at the place
    /// of the shape below that node. The bolt takes that shape's effect shader.
    public func lightningSystems() -> [ParticleSystemDefinition] {
        let parents = nodeParents()
        var visibility = NIFParticleVisibilityFilter(file: self)
        let sequences = attempt { try ControllerSequenceDecoder.sequences(file: self) } ?? []
        return blocks.indices.compactMap { index in
            guard
                let controller = Self.lightningController(blocks[index]),
                controller.base.targetRef >= 0, Int(controller.base.targetRef) < blocks.count
            else { return nil }
            let target = Int(controller.base.targetRef)
            let drawn = boltShape(under: target, parents: parents) ?? target
            guard
                let transform = modelTransform(
                    of: drawn, parents: parents, visibility: &visibility
                )
            else { return nil }
            let shape = attempt { try triShape(of: blocks[drawn]) }
            let shaderRef = shape.map(\.shaderPropertyRef).flatMap { $0 >= 0 ? $0 : nil }
                ?? controller.shaderPropertyRef
            var system = ParticleSystemDefinition(
                name: shape?.object.name, worldTransform: transform, worldSpace: false,
                maxParticles: 0, emitters: [], modifiers: [], subtextureOffsets: [],
                shaderPropertyRef: shaderRef,
                alphaPropertyRef: shape?.alphaPropertyRef ?? -1,
                effectShader: effectShader(at: shaderRef),
                alphaProperty: alphaProperty(at: shape?.alphaPropertyRef ?? -1)
            )
            var lightning = ParticleLightning(controller)
            LightningTrackDecoder(file: self, sequences: sequences)
                .fill(&lightning, controller: controller, index: Int32(index))
            system.lightning = lightning
            system.ancestorNodes = nodeNames(above: drawn, parents: parents)
            return system
        }
    }

    static func lightningController(_ block: NIFBlock) -> NIFLightningController? {
        guard block.typeName == NIFLightningController.typeName else { return nil }
        var reader = BinaryReader(block.data)
        return attempt { try NIFLightningController(reader: &reader) }
    }

    /// The first shape below `node`, in block order. The vanilla bolts keep an empty,
    /// hidden shape there, and the controller fills and shows it.
    private func boltShape(under node: Int, parents: [Int: Int]) -> Int? {
        blocks.indices.first { index in
            let shape = attempt { try triShape(of: blocks[index]) }.flatMap(\.self)
            guard index != node, shape != nil else {
                return false
            }
            var current = parents[index]
            var steps = 0
            while let above = current, steps < 8 {
                if above == node {
                    return true
                }
                current = parents[above]
                steps += 1
            }
            return false
        }
    }

    /// The block's transform in the model, composed up its parents. Nil for a block no
    /// root reaches or a hidden subtree holds. The bolt's own shape is not tested: it is
    /// hidden in the file. The step limit stops a cyclic file.
    private func modelTransform(
        of block: Int, parents: [Int: Int], visibility: inout NIFParticleVisibilityFilter
    ) -> float4x4? {
        var transform = matrix_identity_float4x4
        var current: Int? = block
        var steps = 0
        while let index = current, steps < 64 {
            var reader = BinaryReader(blocks[index].data)
            guard
                let object = attempt({ try NIFObjectPrefix(reader: &reader, header: header) }),
                (index == block && object.isHidden && !object.isEditorMarker)
                || !visibility.drops(object) else { return nil }
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
        return attempt { try NIFEffectShaderProperty(data: blocks[Int(ref)].data, header: header) }
    }

    private func alphaProperty(at ref: Int32) -> NIFAlphaProperty? {
        guard ref >= 0, Int(ref) < blocks.count, blocks[Int(ref)].typeName == "NiAlphaProperty"
        else { return nil }
        return attempt { try NIFAlphaProperty(data: blocks[Int(ref)].data, header: header) }
    }
}
