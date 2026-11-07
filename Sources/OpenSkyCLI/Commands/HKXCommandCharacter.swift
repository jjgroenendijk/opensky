// Character property dump for `openskycli hkx` on a character file: each property's
// type and stored value, so a binding to one can be checked against the data.

import Foundation
import OpenSkyFormatsAnimation

enum HKXCharacterDump {
    static func print(file: HKXFile) {
        guard
            let graph = try? HKXObjectGraph(file: file),
            let object = graph.objects(ofClass: HKBCharacterData.className).first
        else { return }
        let target = HKXPointerTarget(
            sectionIndex: object.sectionIndex, dataOffset: object.dataOffset
        )
        guard let character = HKBCharacterData.decode(at: target, in: graph) else { return }
        let values = character.characterPropertyValues
        Swift.print("character scale: \(character.scale.map { "\($0)" } ?? "none")")
        let mirror = character.mirroredSkeletonInfo.flatMap { graph.className(at: $0) }
        Swift.print("mirrored skeleton info: \(mirror ?? "none")")
        Swift.print("character property values: \(values?.wordValues.count ?? 0) words, "
            + "\(values?.quadValues.count ?? 0) quads, \(values?.variantCount ?? 0) variants")
        for (index, name) in character.characterPropertyNames.enumerated() {
            let info = character.characterPropertyInfos.indices.contains(index)
                ? character.characterPropertyInfos[index] : nil
            let word = values?.wordValues.indices.contains(index) == true
                ? values.map { "\($0.wordValues[index])" } ?? "-" : "-"
            Swift.print("  \(index) \(name ?? "?") : "
                + "\(info?.type?.description ?? "raw \(info?.rawType ?? -1)") word \(word)")
        }
    }
}
