// The character file's property values: what a binding of type 1 reads instead of a
// graph variable. See docs/formats/hkx-behavior.md#hkbcharacterdata-and-hkbcharacterstringdata.

import Foundation
import OpenSkyFormatsAnimation

/// The values of one character's properties, by lowercased name. A graph names its
/// properties in its own list, so a binding finds the value through the name.
nonisolated public struct BehaviorCharacterProperties: Sendable {
    public static let empty = BehaviorCharacterProperties(values: [:], boneWeights: [:])

    /// The bone pairs and axis that mirrored clips use.
    public let mirror: HKBMirroredSkeletonInfo?
    private let values: [String: BehaviorVariableValue]
    private let boneWeights: [String: [Float]]

    public init(
        values: [String: BehaviorVariableValue],
        boneWeights: [String: [Float]],
        mirror: HKBMirroredSkeletonInfo? = nil
    ) {
        self.values = Self.lowercasedKeys(values)
        self.boneWeights = Self.lowercasedKeys(boneWeights)
        self.mirror = mirror
    }

    /// A pointer property keeps the index of its object in the variant list as its word.
    public init(character: HKBCharacterData, in graph: HKXObjectGraph) {
        let set = character.characterPropertyValues
        var values: [String: BehaviorVariableValue] = [:]
        var weights: [String: [Float]] = [:]
        for (index, name) in character.characterPropertyNames.enumerated() {
            guard
                let name, let set, set.wordValues.indices.contains(index),
                character.characterPropertyInfos.indices.contains(index)
            else { continue }
            let word = set.wordValues[index]
            switch character.characterPropertyInfos[index].type {
            case .bool: values[name] = .bool(word != 0)
            case .int8, .int16, .int32: values[name] = .int(Int32(truncatingIfNeeded: word))
            case .real: values[name] = set.realValue(at: index).map(BehaviorVariableValue.real)
            case .vector3, .vector4, .quaternion:
                values[name] = set.quadValues.indices
                    .contains(word) ? .quad(set.quadValues[word]) : nil
            case .pointer:
                weights[name] = set.variantTargets.indices.contains(word)
                    ? set.variantTargets[word]
                    .flatMap { HKBBoneWeightArray.decode(at: $0, in: graph) }?.boneWeights
                    : nil
            case .invalid, nil: continue
            }
        }
        self.init(
            values: values,
            boneWeights: weights,
            mirror: character.mirroredSkeletonInfo.flatMap {
                HKBMirroredSkeletonInfo.decode(at: $0, in: graph)
            }
        )
    }

    private static func lowercasedKeys<Value>(_ map: [String: Value]) -> [String: Value] {
        Dictionary(map.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
    }

    public func value(named name: String) -> BehaviorVariableValue? {
        values[name.lowercased()]
    }

    public func boneWeights(named name: String) -> [Float]? {
        boneWeights[name.lowercased()]
    }

    /// True for a property that holds an object, such as a bone weight array.
    public func holdsObject(named name: String) -> Bool {
        boneWeights[name.lowercased()] != nil
    }
}

nonisolated extension BehaviorGraphInstance {
    /// The bone weight array a character-property binding puts on `path`, or nil.
    func characterBoneWeights(of node: BehaviorCompiledNode, path: String) -> [Float]? {
        guard let compiled = node.bindings else { return nil }
        for (index, binding) in compiled.bindings.enumerated()
            where binding.bindingType == 1 && compiled.paths[index] == path
        {
            return characterProperty(binding).flatMap(characterProperties.boneWeights(named:))
        }
        return nil
    }
}
