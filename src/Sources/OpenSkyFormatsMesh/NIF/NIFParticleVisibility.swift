// Which subtrees the particle walk drops: hidden objects and editor markers, as the mesh
// walk does. See docs/formats/nif-particles.md#from-scene-graph-to-particle-system.

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFFile {
    /// Decides whether an object and its children are never drawn. One value serves one
    /// file; it finds the animated names on the first hidden object only.
    struct ParticleVisibilityFilter {
        let file: NIFFile
        private var animatedNames: Set<String>?

        init(file: NIFFile) {
            self.file = file
        }

        /// True for an editor marker, and for a hidden object that nothing can show later.
        mutating func drops(_ object: NIFObjectPrefix) -> Bool {
            if NIFFile.Flattener.isEditorMarker(object.name) {
                return true
            }
            guard object.isHidden else { return false }
            if file.hasVisibilityController(from: object.controllerRef) {
                return false
            }
            guard let name = object.name else { return true }
            let names = animatedNames ?? file.namesWithAnimatedVisibility()
            animatedNames = names
            return !names.contains(name)
        }
    }

    /// True when the controller chain from `ref` holds a `NiVisController`. The step limit
    /// stops a cyclic chain.
    private func hasVisibilityController(from ref: Int32) -> Bool {
        var current = ref
        var steps = 0
        while current >= 0, Int(current) < blocks.count, steps < 32 {
            let block = blocks[Int(current)]
            if block.typeName == ParticleControllerDecoder.visibilityControllerType {
                return true
            }
            var reader = BinaryReader(block.data)
            guard let base = attempt({ try NIFTimeController(reader: &reader) }) else {
                return false
            }
            current = base.nextControllerRef
            steps += 1
        }
        return false
    }

    /// The objects a sequence's visibility track names, and the ones a behaviour graph
    /// shows through an `hkVis:` extra data value.
    private func namesWithAnimatedVisibility() -> Set<String> {
        var names: Set<String> = []
        for sequence in attempt({ try sequences() }) ?? [] {
            for track in sequence.tracks {
                if case let .node(name) = track.target, case .visibility = track.channel {
                    names.insert(name)
                }
            }
        }
        let prefix = NIFEffectPose.visibilityExtraDataPrefix
        for string in header.strings where string.hasPrefix(prefix) {
            names.insert(String(string.dropFirst(prefix.count)))
        }
        return names
    }
}
